#!/usr/bin/env python3
import csv
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QKeySequence
from PyQt6.QtWidgets import (
    QApplication,
    QCheckBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QKeySequenceEdit,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)


CONFIG_HOME = Path.home() / ".config"
if "XDG_CONFIG_HOME" in os.environ:
    CONFIG_HOME = Path(os.environ["XDG_CONFIG_HOME"])
SIGS_CONFIG_DIR = CONFIG_HOME / "sigs"
ALLOWLIST = SIGS_CONFIG_DIR / "allowlist"
KGLOBALSHORTCUTSRC = Path.home() / ".config" / "kglobalshortcutsrc"


@dataclass
class Action:
    component: str
    key: str
    friendly_name: str
    active_shortcuts: list[str]
    default_shortcuts: list[str]

    @property
    def action_id(self) -> str:
        return f"{self.component}/{self.key}"

    @property
    def shortcut_text(self) -> str:
        shortcuts = self.active_shortcuts or self.default_shortcuts
        return ", ".join(shortcuts)


def parse_shortcuts(value: str) -> list[str]:
    if not value or value == "none":
        return []
    return [shortcut for shortcut in value.split("\\t") if shortcut and shortcut != "none"]


def parse_action_value(value: str) -> tuple[list[str], list[str], str]:
    try:
        fields = next(csv.reader([value], escapechar="\\"))
    except csv.Error:
        fields = value.split(",", 2)

    while len(fields) < 3:
        fields.append("")

    return parse_shortcuts(fields[0]), parse_shortcuts(fields[1]), fields[2]


def load_actions() -> list[Action]:
    actions: list[Action] = []
    component = ""

    for raw_line in KGLOBALSHORTCUTSRC.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            component = line[1:-1]
            continue
        if "=" not in line or not component:
            continue

        key, value = line.split("=", 1)
        if key.startswith("_k_"):
            continue

        active, default, friendly_name = parse_action_value(value)
        actions.append(Action(component, key, friendly_name or key, active, default))

    return actions


def load_allowlist() -> set[str]:
    SIGS_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if not ALLOWLIST.exists():
        return set()

    allowed: set[str] = set()
    for raw_line in ALLOWLIST.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if line:
            allowed.add(line)
    return allowed


def write_allowlist(action_ids: list[str]) -> None:
    SIGS_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    header = """# Selective global shortcut action allowlist.
#
# Format:
#   component/action
#
# These are KDE global shortcut action identifiers, not physical key bindings.
"""
    ALLOWLIST.write_text(header + "\n".join(action_ids) + "\n", encoding="utf-8")


def apply_allowlist(action_ids: list[str]) -> None:
    array_arg = "array:string:" + ",".join(action_ids)
    subprocess.run(
        [
            "dbus-send",
            "--session",
            "--dest=org.kde.kglobalaccel",
            "--type=method_call",
            "/kglobalaccel",
            "org.kde.KGlobalAccel.setSelectiveGlobalShortcuts",
            array_arg,
        ],
        check=True,
    )


def set_global_shortcut_capture(enabled: bool) -> None:
    subprocess.run(
        [
            "dbus-send",
            "--session",
            "--dest=org.kde.kglobalaccel",
            "--type=method_call",
            "/kglobalaccel",
            "org.kde.KGlobalAccel.blockGlobalShortcuts",
            f"boolean:{str(enabled).lower()}",
        ],
        check=False,
    )


class ShortcutCaptureEdit(QKeySequenceEdit):
    def focusInEvent(self, event) -> None:
        set_global_shortcut_capture(True)
        super().focusInEvent(event)

    def focusOutEvent(self, event) -> None:
        super().focusOutEvent(event)
        set_global_shortcut_capture(False)


class SelectiveShortcutsWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Selective Global Shortcut Actions")
        self.resize(1100, 720)

        self.actions = load_actions()
        self.allowed = load_allowlist()
        self.row_actions: list[Action] = []

        self.search = QLineEdit()
        self.search.setPlaceholderText("Search component, action, identifier, or current shortcut")
        self.search.textChanged.connect(self.refresh_table)

        self.shortcut_edit = ShortcutCaptureEdit()
        self.shortcut_edit.setClearButtonEnabled(True)
        self.shortcut_edit.keySequenceChanged.connect(self.refresh_table)

        self.only_matching_shortcut = QCheckBox("Show only actions using this shortcut")
        self.only_matching_shortcut.stateChanged.connect(self.refresh_table)

        shortcut_row = QHBoxLayout()
        shortcut_row.addWidget(QLabel("Shortcut recogniser:"))
        shortcut_row.addWidget(self.shortcut_edit, 1)
        shortcut_row.addWidget(self.only_matching_shortcut)

        self.table = QTableWidget(0, 5)
        self.table.setHorizontalHeaderLabels(["Allowed", "Component", "Action", "Identifier", "Current shortcuts"])
        self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        self.table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
        self.table.horizontalHeader().setSectionResizeMode(4, QHeaderView.ResizeMode.Stretch)
        self.table.itemChanged.connect(self.item_changed)

        self.status = QLabel()

        reload_button = QPushButton("Reload")
        reload_button.clicked.connect(self.reload)

        save_button = QPushButton("Save And Apply")
        save_button.clicked.connect(self.save_and_apply)

        close_button = QPushButton("Close")
        close_button.clicked.connect(self.close)

        button_row = QHBoxLayout()
        button_row.addWidget(self.status, 1)
        button_row.addWidget(reload_button)
        button_row.addWidget(save_button)
        button_row.addWidget(close_button)

        layout = QVBoxLayout()
        layout.addWidget(QLabel("Select KDE global shortcut actions to keep active while the selective window rule is active."))
        layout.addWidget(self.search)
        layout.addLayout(shortcut_row)
        layout.addWidget(self.table, 1)
        layout.addLayout(button_row)

        container = QWidget()
        container.setLayout(layout)
        self.setCentralWidget(container)

        self.refresh_table()

    def closeEvent(self, event) -> None:
        set_global_shortcut_capture(False)
        super().closeEvent(event)

    def item_changed(self, item: QTableWidgetItem) -> None:
        if item.column() != 0:
            return
        action = self.row_actions[item.row()]
        if item.checkState() == Qt.CheckState.Checked:
            self.allowed.add(action.action_id)
        else:
            self.allowed.discard(action.action_id)
        self.update_status()

    def shortcut_filter(self) -> str:
        return self.shortcut_edit.keySequence().toString(QKeySequence.SequenceFormat.PortableText)

    def action_matches(self, action: Action) -> bool:
        search = self.search.text().strip().lower()
        shortcut = self.shortcut_filter()

        haystack = " ".join(
            [
                action.component,
                action.key,
                action.friendly_name,
                action.action_id,
                action.shortcut_text,
            ]
        ).lower()
        if search and search not in haystack:
            return False

        if self.only_matching_shortcut.isChecked() and shortcut:
            known_shortcuts = action.active_shortcuts + action.default_shortcuts
            return shortcut in known_shortcuts

        return True

    def refresh_table(self) -> None:
        self.table.blockSignals(True)
        self.table.setRowCount(0)
        self.row_actions = []

        for action in self.actions:
            if not self.action_matches(action):
                continue

            row = self.table.rowCount()
            self.table.insertRow(row)
            self.row_actions.append(action)

            allowed_item = QTableWidgetItem()
            allowed_item.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled)
            allowed_item.setCheckState(Qt.CheckState.Checked if action.action_id in self.allowed else Qt.CheckState.Unchecked)
            self.table.setItem(row, 0, allowed_item)

            for column, value in enumerate(
                [action.component, action.friendly_name, action.action_id, action.shortcut_text],
                start=1,
            ):
                item = QTableWidgetItem(value)
                item.setFlags(Qt.ItemFlag.ItemIsSelectable | Qt.ItemFlag.ItemIsEnabled)
                self.table.setItem(row, column, item)

        self.table.blockSignals(False)
        self.update_status()

    def reload(self) -> None:
        self.actions = load_actions()
        self.allowed = load_allowlist()
        self.refresh_table()

    def update_status(self) -> None:
        self.status.setText(f"{len(self.allowed)} allowed actions, {self.table.rowCount()} visible actions")

    def save_and_apply(self) -> None:
        action_ids = sorted(self.allowed)
        try:
            write_allowlist(action_ids)
            apply_allowlist(action_ids)
        except Exception as error:
            QMessageBox.critical(self, "Apply Failed", str(error))
            return
        QMessageBox.information(self, "Applied", "Selective action allowlist saved and applied.")


def main() -> int:
    app = QApplication(sys.argv)
    window = SelectiveShortcutsWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
