"""Main window for the prompt builder.

Layout (left to right):
- Templates list (left rail)
- Per-template form (middle column)
- Live prompt preview + copy button (right column)
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from PyQt6.QtCore import Qt, QSize
from PyQt6.QtGui import QGuiApplication, QFont, QAction, QKeySequence
from PyQt6.QtWidgets import (
    QApplication,
    QCheckBox,
    QComboBox,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QPlainTextEdit,
    QPushButton,
    QScrollArea,
    QSpinBox,
    QSplitter,
    QStatusBar,
    QVBoxLayout,
    QWidget,
)

from .templates import TEMPLATES, Template, Field, list_templates


class PathEdit(QWidget):
    """Line edit + Browse button for path fields."""

    def __init__(self, placeholder: str = "", file_mode: bool = False, parent=None):
        super().__init__(parent)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)
        self.edit = QLineEdit()
        self.edit.setPlaceholderText(placeholder)
        self.button = QPushButton("Browse…")
        self.button.setMaximumWidth(90)
        self.button.clicked.connect(self._browse)
        layout.addWidget(self.edit)
        layout.addWidget(self.button)
        self._file_mode = file_mode

    def _browse(self):
        start = self.edit.text().strip() or str(Path.home())
        if self._file_mode:
            path, _ = QFileDialog.getOpenFileName(self, "Select file", start)
        else:
            path = QFileDialog.getExistingDirectory(self, "Select directory", start)
        if path:
            self.edit.setText(path)

    def text(self) -> str:
        return self.edit.text().strip()

    def setText(self, value: str):
        self.edit.setText(value)

    def textChanged(self):
        return self.edit.textChanged


class PathsEdit(QPlainTextEdit):
    """Multi-line path editor for overnight multi-repo selection."""

    def __init__(self, placeholder: str = "", parent=None):
        super().__init__(parent)
        self.setPlaceholderText(placeholder)
        self.setMinimumHeight(80)
        self.setMaximumHeight(120)


class FormBuilder:
    """Builds Qt widgets from a Template's field list and tracks values."""

    def __init__(self, template: Template, on_change):
        self.template = template
        self._on_change = on_change
        self._widgets: dict[str, QWidget] = {}
        self.container = QWidget()
        self.layout = QFormLayout(self.container)
        self.layout.setSpacing(10)
        self.layout.setContentsMargins(12, 8, 12, 12)
        self.layout.setFieldGrowthPolicy(
            QFormLayout.FieldGrowthPolicy.AllNonFixedFieldsGrow
        )
        self._build()

    def _build(self):
        for f in self.template.fields:
            label = QLabel(f.label)
            label.setWordWrap(True)
            widget = self._make_widget(f)
            self._widgets[f.key] = widget

            if f.help:
                row = QWidget()
                row_layout = QVBoxLayout(row)
                row_layout.setContentsMargins(0, 0, 0, 0)
                row_layout.setSpacing(2)
                row_layout.addWidget(widget)
                help_lbl = QLabel(f.help)
                help_lbl.setObjectName("help_text")
                help_lbl.setWordWrap(True)
                row_layout.addWidget(help_lbl)
                self.layout.addRow(label, row)
            else:
                self.layout.addRow(label, widget)

    def _make_widget(self, f: Field) -> QWidget:
        if f.kind == "path":
            w = PathEdit(placeholder=f.placeholder, file_mode=False)
            if f.default:
                w.setText(str(f.default))
            w.edit.textChanged.connect(self._on_change)
            return w

        if f.kind == "paths":
            w = PathsEdit(placeholder=f.placeholder)
            if f.default:
                w.setPlainText(str(f.default))
            w.textChanged.connect(self._on_change)
            return w

        if f.kind == "text":
            w = QLineEdit()
            w.setPlaceholderText(f.placeholder)
            if f.default:
                w.setText(str(f.default))
            w.textChanged.connect(self._on_change)
            return w

        if f.kind == "multiline":
            w = QPlainTextEdit()
            w.setPlaceholderText(f.placeholder)
            if f.default:
                w.setPlainText(str(f.default))
            w.setMaximumHeight(120)
            w.textChanged.connect(self._on_change)
            return w

        if f.kind == "int":
            w = QSpinBox()
            if f.min_value is not None:
                w.setMinimum(f.min_value)
            else:
                w.setMinimum(0)
            if f.max_value is not None:
                w.setMaximum(f.max_value)
            else:
                w.setMaximum(99999)
            w.setValue(int(f.default) if f.default else 0)
            w.valueChanged.connect(self._on_change)
            return w

        if f.kind == "choice":
            w = QComboBox()
            w.addItems(f.choices)
            if f.default in f.choices:
                w.setCurrentText(str(f.default))
            w.currentTextChanged.connect(self._on_change)
            return w

        if f.kind == "checkbox":
            w = QCheckBox()
            w.setChecked(bool(f.default))
            w.toggled.connect(self._on_change)
            return w

        return QLineEdit()  # fallback

    def values(self) -> dict[str, Any]:
        out: dict[str, Any] = {}
        for f in self.template.fields:
            w = self._widgets[f.key]
            if isinstance(w, PathEdit):
                out[f.key] = w.text()
            elif isinstance(w, PathsEdit):
                out[f.key] = w.toPlainText()
            elif isinstance(w, QPlainTextEdit):
                out[f.key] = w.toPlainText()
            elif isinstance(w, QLineEdit):
                out[f.key] = w.text()
            elif isinstance(w, QSpinBox):
                out[f.key] = w.value()
            elif isinstance(w, QComboBox):
                out[f.key] = w.currentText()
            elif isinstance(w, QCheckBox):
                out[f.key] = w.isChecked()
        return out


class PromptBuilderWindow(QMainWindow):

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Octopus Factory — Prompt Builder")
        self.resize(1280, 820)
        self.setMinimumSize(QSize(960, 600))

        self._current_form: FormBuilder | None = None
        self._current_template_key: str | None = None
        self._build_ui()
        self._select_first_template()

    def _build_ui(self):
        # ─── Templates list (left rail) ───
        self.template_list = QListWidget()
        self.template_list.setMinimumWidth(220)
        self.template_list.setMaximumWidth(280)
        for tpl in list_templates():
            item = QListWidgetItem(tpl.label)
            item.setData(Qt.ItemDataRole.UserRole, tpl.key)
            item.setToolTip(tpl.description)
            self.template_list.addItem(item)
        self.template_list.currentItemChanged.connect(self._on_template_selected)

        # ─── Form area (middle) ───
        form_header_label = QLabel("Configure")
        form_header_label.setObjectName("section_header")
        self.form_description = QLabel("")
        self.form_description.setObjectName("help_text")
        self.form_description.setWordWrap(True)

        self.form_scroll = QScrollArea()
        self.form_scroll.setWidgetResizable(True)
        self.form_scroll.setMinimumWidth(420)

        form_col = QWidget()
        form_layout = QVBoxLayout(form_col)
        form_layout.setContentsMargins(16, 16, 16, 16)
        form_layout.setSpacing(8)
        form_layout.addWidget(form_header_label)
        form_layout.addWidget(self.form_description)
        form_layout.addWidget(self.form_scroll, 1)

        # ─── Preview area (right) ───
        preview_header = QLabel("Prompt preview")
        preview_header.setObjectName("section_header")

        self.preview = QPlainTextEdit()
        self.preview.setObjectName("preview")
        self.preview.setReadOnly(False)  # let user tweak before copy
        self.preview.setLineWrapMode(QPlainTextEdit.LineWrapMode.NoWrap)
        mono = QFont("Cascadia Code, JetBrains Mono, Consolas, Menlo, monospace", 10)
        self.preview.setFont(mono)
        self.preview.textChanged.connect(self._update_count)

        self.copy_btn = QPushButton("Copy to clipboard")
        self.copy_btn.setObjectName("primary")
        self.copy_btn.setMinimumHeight(36)
        self.copy_btn.clicked.connect(self._copy_to_clipboard)

        self.save_btn = QPushButton("Save as .txt…")
        self.save_btn.setMinimumHeight(36)
        self.save_btn.clicked.connect(self._save_as_file)

        self.reset_btn = QPushButton("Reset")
        self.reset_btn.setMinimumHeight(36)
        self.reset_btn.clicked.connect(self._reset_form)

        button_row = QHBoxLayout()
        button_row.addWidget(self.copy_btn, 2)
        button_row.addWidget(self.save_btn, 1)
        button_row.addWidget(self.reset_btn, 1)

        self.count_label = QLabel("0 lines · 0 chars")
        self.count_label.setObjectName("footer_count")
        self.count_label.setAlignment(Qt.AlignmentFlag.AlignRight)

        preview_col = QWidget()
        preview_layout = QVBoxLayout(preview_col)
        preview_layout.setContentsMargins(16, 16, 16, 16)
        preview_layout.setSpacing(8)
        preview_layout.addWidget(preview_header)
        preview_layout.addWidget(self.preview, 1)
        preview_layout.addWidget(self.count_label)
        preview_layout.addLayout(button_row)

        # ─── Splitter ───
        splitter = QSplitter(Qt.Orientation.Horizontal)
        splitter.addWidget(self.template_list)
        splitter.addWidget(form_col)
        splitter.addWidget(preview_col)
        splitter.setSizes([240, 480, 560])
        splitter.setStretchFactor(0, 0)
        splitter.setStretchFactor(1, 1)
        splitter.setStretchFactor(2, 1)
        splitter.setHandleWidth(4)

        self.setCentralWidget(splitter)

        # ─── Status bar + shortcuts ───
        self.setStatusBar(QStatusBar())
        self.statusBar().showMessage("Ready. Pick a template on the left.")

        copy_action = QAction("Copy", self)
        copy_action.setShortcut(QKeySequence("Ctrl+Shift+C"))
        copy_action.triggered.connect(self._copy_to_clipboard)
        self.addAction(copy_action)

        reset_action = QAction("Reset", self)
        reset_action.setShortcut(QKeySequence("Ctrl+R"))
        reset_action.triggered.connect(self._reset_form)
        self.addAction(reset_action)

    # ─── Template lifecycle ───

    def _select_first_template(self):
        if self.template_list.count():
            self.template_list.setCurrentRow(0)

    def _on_template_selected(self, current: QListWidgetItem, previous):
        if not current:
            return
        key = current.data(Qt.ItemDataRole.UserRole)
        self._load_template(key)

    def _load_template(self, key: str):
        tpl = TEMPLATES[key]
        self._current_template_key = key
        self.form_description.setText(tpl.description)

        form = FormBuilder(tpl, on_change=self._regenerate)
        self._current_form = form
        self.form_scroll.setWidget(form.container)
        self._regenerate()
        self.statusBar().showMessage(f"Configuring: {tpl.label}")

    def _regenerate(self):
        if not self._current_form or not self._current_template_key:
            return
        tpl = TEMPLATES[self._current_template_key]
        try:
            text = tpl.render(self._current_form.values())
        except Exception as exc:
            text = f"# Render error: {exc}"
        # Preserve cursor position when re-rendering
        cursor_pos = self.preview.textCursor().position()
        self.preview.blockSignals(True)
        self.preview.setPlainText(text)
        self.preview.blockSignals(False)
        cursor = self.preview.textCursor()
        cursor.setPosition(min(cursor_pos, len(text)))
        self.preview.setTextCursor(cursor)
        self._update_count()

    # ─── Actions ───

    def _copy_to_clipboard(self):
        text = self.preview.toPlainText()
        QGuiApplication.clipboard().setText(text)
        self.statusBar().showMessage(f"Copied {len(text)} characters to clipboard.", 4000)

    def _save_as_file(self):
        text = self.preview.toPlainText()
        if not text.strip():
            self.statusBar().showMessage("Nothing to save — preview is empty.", 4000)
            return
        suggested = "prompt.txt"
        if self._current_template_key:
            suggested = f"prompt-{self._current_template_key.replace('_', '-')}.txt"
        path, _ = QFileDialog.getSaveFileName(
            self, "Save prompt as text file",
            os.path.join(str(Path.home()), suggested),
            "Text files (*.txt);;All files (*.*)",
        )
        if path:
            try:
                Path(path).write_text(text, encoding="utf-8")
                self.statusBar().showMessage(f"Saved to {path}", 5000)
            except OSError as exc:
                self.statusBar().showMessage(f"Save failed: {exc}", 6000)

    def _reset_form(self):
        if self._current_template_key:
            self._load_template(self._current_template_key)
            self.statusBar().showMessage("Form reset to defaults.", 3000)

    def _update_count(self):
        text = self.preview.toPlainText()
        lines = text.count("\n") + (1 if text else 0)
        self.count_label.setText(f"{lines} lines · {len(text)} chars")
