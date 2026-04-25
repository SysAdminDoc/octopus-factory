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

from PyQt6.QtCore import Qt, QSize, QSettings, QTimer
from PyQt6.QtGui import QGuiApplication, QFont, QAction, QKeySequence
from PyQt6.QtWidgets import (
    QApplication,
    QCheckBox,
    QComboBox,
    QFileDialog,
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

    def __init__(
        self,
        placeholder: str = "",
        file_mode: bool = False,
        file_filter: str = "All files (*.*)",
        parent=None,
    ):
        super().__init__(parent)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)
        self.edit = QLineEdit()
        self.edit.setPlaceholderText(placeholder)
        self.button = QPushButton("Browse…")
        self.button.setObjectName("secondary")
        self.button.setMinimumWidth(92)
        self.button.clicked.connect(self._browse)
        layout.addWidget(self.edit)
        layout.addWidget(self.button)
        self._file_mode = file_mode
        self._file_filter = file_filter

    def _browse(self):
        start = self.edit.text().strip() or str(Path.home())
        if self._file_mode:
            path, _ = QFileDialog.getOpenFileName(
                self, "Select file", start, self._file_filter
            )
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


def _template_group(key: str) -> str:
    """Return a compact category label for navigation grouping."""
    if key in {"factory_loop", "overnight", "single_task"}:
        return "Run"
    if key in {"audit_only", "plan", "roadmap_research"}:
        return "Review"
    if key in {"release_build", "ai_scrub"}:
        return "Release"
    if key.startswith("pdf_"):
        return "PDF"
    return "Prompt"


class FormBuilder:
    """Builds Qt widgets from a Template's field list and tracks values."""

    def __init__(self, template: Template, on_change):
        self.template = template
        self._on_change = on_change
        self._widgets: dict[str, QWidget] = {}
        self.container = QWidget()
        self.layout = QVBoxLayout(self.container)
        self.layout.setContentsMargins(4, 10, 8, 12)
        self.layout.setSpacing(12)
        self._build()

    def _build(self):
        for f in self.template.fields:
            row = QWidget()
            row.setObjectName("form_row")
            row_layout = QVBoxLayout(row)
            row_layout.setContentsMargins(0, 0, 0, 0)
            row_layout.setSpacing(5)

            label = QLabel(f.label)
            label.setObjectName("field_label")
            label.setWordWrap(True)
            widget = self._make_widget(f)
            widget.setAccessibleName(f.label)
            self._widgets[f.key] = widget

            row_layout.addWidget(label)
            row_layout.addWidget(widget)
            if f.help:
                help_lbl = QLabel(f.help)
                help_lbl.setObjectName("help_text")
                help_lbl.setTextInteractionFlags(
                    Qt.TextInteractionFlag.TextSelectableByMouse
                )
                help_lbl.setWordWrap(True)
                row_layout.addWidget(help_lbl)
            self.layout.addWidget(row)
        self.layout.addStretch(1)

    def _make_widget(self, f: Field) -> QWidget:
        if f.kind == "path":
            is_pdf_source = f.key in {"pdf_path", "source_pdf"}
            file_filter = (
                "PDF files (*.pdf);;All files (*.*)"
                if is_pdf_source
                else "All files (*.*)"
            )
            w = PathEdit(
                placeholder=f.placeholder,
                file_mode=is_pdf_source,
                file_filter=file_filter,
            )
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
            w.setText("Enabled")
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
        self._rendering_preview = False
        self._preview_is_manual = False
        self._empty_required_fields: list[str] = []
        self._settings = QSettings("octopus-factory", "Prompt Builder")
        self._copy_reset_timer = QTimer(self)
        self._copy_reset_timer.setSingleShot(True)
        self._copy_reset_timer.timeout.connect(self._restore_copy_button)
        self._build_ui()
        self._restore_ui_state()

    def _build_ui(self):
        # ─── Templates list (left rail) ───
        app_title = QLabel("Prompt Builder")
        app_title.setObjectName("app_title")
        app_subtitle = QLabel(
            "Build canonical octopus-factory prompts without hand-editing flags."
        )
        app_subtitle.setObjectName("app_subtitle")
        app_subtitle.setWordWrap(True)

        self.search_edit = QLineEdit()
        self.search_edit.setObjectName("search")
        self.search_edit.setPlaceholderText("Search prompt types")
        self.search_edit.setAccessibleName("Search prompt types")
        self.search_edit.setClearButtonEnabled(True)
        self.search_edit.textChanged.connect(self._filter_templates)

        self.no_results_label = QLabel("No prompt types match this search.")
        self.no_results_label.setObjectName("empty_state")
        self.no_results_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.no_results_label.setWordWrap(True)
        self.no_results_label.hide()

        self.template_list = QListWidget()
        self.template_list.setObjectName("template_list")
        self.template_list.setMinimumWidth(220)
        self.template_list.setMaximumWidth(310)
        for tpl in list_templates():
            group = _template_group(tpl.key)
            item = QListWidgetItem(f"{tpl.label}\n{group} · {tpl.description}")
            item.setData(Qt.ItemDataRole.UserRole, tpl.key)
            item.setData(Qt.ItemDataRole.UserRole + 1, group)
            item.setData(
                Qt.ItemDataRole.UserRole + 2,
                f"{tpl.label} {group} {tpl.description}".lower(),
            )
            item.setToolTip(tpl.description)
            item.setSizeHint(QSize(220, 58))
            self.template_list.addItem(item)
        self.template_list.currentItemChanged.connect(self._on_template_selected)

        nav_footer = QLabel(
            "Ctrl+Shift+C copies the preview. Ctrl+R resets the active template."
        )
        nav_footer.setObjectName("nav_footer")
        nav_footer.setWordWrap(True)

        nav_col = QWidget()
        nav_col.setObjectName("nav_panel")
        nav_layout = QVBoxLayout(nav_col)
        nav_layout.setContentsMargins(16, 16, 14, 16)
        nav_layout.setSpacing(12)
        nav_layout.addWidget(app_title)
        nav_layout.addWidget(app_subtitle)
        nav_layout.addWidget(self.search_edit)
        nav_layout.addWidget(self.no_results_label)
        nav_layout.addWidget(self.template_list, 1)
        nav_layout.addWidget(nav_footer)

        # ─── Form area (middle) ───
        self.form_group = QLabel("Template")
        self.form_group.setObjectName("section_kicker")
        self.form_title = QLabel("Configure")
        self.form_title.setObjectName("section_title")
        self.form_title.setWordWrap(True)
        form_header_label = self.form_title
        form_header_label.setObjectName("section_header")
        self.form_description = QLabel("")
        self.form_description.setObjectName("help_text")
        self.form_description.setWordWrap(True)
        self.form_description.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )

        self.form_scroll = QScrollArea()
        self.form_scroll.setObjectName("panel")
        self.form_scroll.setWidgetResizable(True)
        self.form_scroll.setMinimumWidth(420)

        form_col = QWidget()
        form_col.setObjectName("content_panel")
        form_layout = QVBoxLayout(form_col)
        form_layout.setContentsMargins(20, 18, 18, 18)
        form_layout.setSpacing(8)
        form_layout.addWidget(self.form_group)
        form_layout.addWidget(form_header_label)
        form_layout.addWidget(self.form_description)
        self.form_hint = QLabel(
            "Required path fields can stay as placeholders until you are ready to paste."
        )
        self.form_hint.setObjectName("inline_notice")
        self.form_hint.setWordWrap(True)
        form_layout.addWidget(self.form_hint)
        form_layout.addWidget(self.form_scroll, 1)

        # ─── Preview area (right) ───
        preview_group = QLabel("Output")
        preview_group.setObjectName("section_kicker")
        preview_header = QLabel("Prompt preview")
        preview_header.setObjectName("section_header")

        self.preview_state = QLabel("Live preview")
        self.preview_state.setObjectName("status_pill")

        self.preview = QPlainTextEdit()
        self.preview.setObjectName("preview")
        self.preview.setReadOnly(False)  # let user tweak before copy
        self.preview.setLineWrapMode(QPlainTextEdit.LineWrapMode.NoWrap)
        mono = QFont("Cascadia Code, JetBrains Mono, Consolas, Menlo, monospace", 10)
        self.preview.setFont(mono)
        self.preview.textChanged.connect(self._on_preview_text_changed)
        self.preview.setPlaceholderText("The generated prompt will appear here.")

        self.wrap_toggle = QCheckBox("Wrap lines")
        self.wrap_toggle.setObjectName("compact_checkbox")
        self.wrap_toggle.setToolTip("Toggle wrapping for reading long generated prompts.")
        self.wrap_toggle.toggled.connect(self._toggle_preview_wrap)

        self.copy_btn = QPushButton("Copy")
        self.copy_btn.setObjectName("primary")
        self.copy_btn.setMinimumHeight(40)
        self.copy_btn.setToolTip("Copy the current preview to the clipboard.")
        self.copy_btn.clicked.connect(self._copy_to_clipboard)

        self.save_btn = QPushButton("Save…")
        self.save_btn.setObjectName("secondary")
        self.save_btn.setMinimumHeight(40)
        self.save_btn.setToolTip("Save the current preview as a text file.")
        self.save_btn.clicked.connect(self._save_as_file)

        self.regenerate_btn = QPushButton("Regenerate")
        self.regenerate_btn.setObjectName("secondary")
        self.regenerate_btn.setMinimumHeight(40)
        self.regenerate_btn.setToolTip("Restore the preview from the current form values.")
        self.regenerate_btn.clicked.connect(self._regenerate)

        self.reset_btn = QPushButton("Reset")
        self.reset_btn.setObjectName("secondary")
        self.reset_btn.setMinimumHeight(40)
        self.reset_btn.clicked.connect(self._reset_form)

        button_row = QHBoxLayout()
        button_row.setSpacing(10)
        button_row.addWidget(self.copy_btn, 2)
        button_row.addWidget(self.save_btn, 1)
        button_row.addWidget(self.regenerate_btn, 1)
        button_row.addWidget(self.reset_btn, 1)

        self.count_label = QLabel("0 lines · 0 chars")
        self.count_label.setObjectName("footer_count")
        self.count_label.setAlignment(Qt.AlignmentFlag.AlignRight)

        preview_meta_row = QHBoxLayout()
        preview_meta_row.addWidget(self.wrap_toggle)
        preview_meta_row.addStretch(1)
        preview_meta_row.addWidget(self.count_label)

        preview_col = QWidget()
        preview_col.setObjectName("content_panel")
        preview_layout = QVBoxLayout(preview_col)
        preview_layout.setContentsMargins(18, 18, 20, 18)
        preview_layout.setSpacing(10)
        preview_layout.addWidget(preview_group)
        preview_header_row = QHBoxLayout()
        preview_header_row.addWidget(preview_header)
        preview_header_row.addStretch(1)
        preview_header_row.addWidget(self.preview_state)
        preview_layout.addLayout(preview_header_row)
        preview_layout.addWidget(self.preview, 1)
        preview_layout.addLayout(preview_meta_row)
        preview_layout.addLayout(button_row)

        # ─── Splitter ───
        self.splitter = QSplitter(Qt.Orientation.Horizontal)
        self.splitter.addWidget(nav_col)
        self.splitter.addWidget(form_col)
        self.splitter.addWidget(preview_col)
        self.splitter.setSizes([285, 465, 610])
        self.splitter.setStretchFactor(0, 0)
        self.splitter.setStretchFactor(1, 1)
        self.splitter.setStretchFactor(2, 1)
        self.splitter.setHandleWidth(6)

        self.setCentralWidget(self.splitter)

        # ─── Status bar + shortcuts ───
        self.setStatusBar(QStatusBar())
        self.statusBar().showMessage("Ready. Pick a prompt type or start searching.")

        copy_action = QAction("Copy", self)
        copy_action.setShortcut(QKeySequence("Ctrl+Shift+C"))
        copy_action.triggered.connect(self._copy_to_clipboard)
        self.addAction(copy_action)

        reset_action = QAction("Reset", self)
        reset_action.setShortcut(QKeySequence("Ctrl+R"))
        reset_action.triggered.connect(self._reset_form)
        self.addAction(reset_action)

        save_action = QAction("Save prompt", self)
        save_action.setShortcut(QKeySequence("Ctrl+S"))
        save_action.triggered.connect(self._save_as_file)
        self.addAction(save_action)

        regenerate_action = QAction("Regenerate preview", self)
        regenerate_action.setShortcut(QKeySequence("F5"))
        regenerate_action.triggered.connect(self._regenerate)
        self.addAction(regenerate_action)

        search_action = QAction("Search prompt types", self)
        search_action.setShortcut(QKeySequence("Ctrl+F"))
        search_action.triggered.connect(lambda: self.search_edit.setFocus())
        self.addAction(search_action)

    # ─── Template lifecycle ───

    def _select_first_template(self):
        if self.template_list.count():
            self.template_list.setCurrentRow(0)

    def _restore_ui_state(self):
        geometry = self._settings.value("window/geometry")
        if geometry:
            self.restoreGeometry(geometry)

        splitter_state = self._settings.value("window/splitterState")
        if splitter_state:
            self.splitter.restoreState(splitter_state)

        self.wrap_toggle.setChecked(
            self._settings.value("preview/wrapLines", False, type=bool)
        )

        saved_key = self._settings.value("template/current", "", type=str)
        if saved_key:
            for row in range(self.template_list.count()):
                item = self.template_list.item(row)
                if item.data(Qt.ItemDataRole.UserRole) == saved_key:
                    self.template_list.setCurrentRow(row)
                    break

        if not self.template_list.currentItem():
            self._select_first_template()

    def _filter_templates(self, query: str):
        needle = query.strip().lower()
        first_visible = None
        current = self.template_list.currentItem()
        current_hidden = False

        for row in range(self.template_list.count()):
            item = self.template_list.item(row)
            haystack = item.data(Qt.ItemDataRole.UserRole + 2)
            hidden = bool(needle and needle not in haystack)
            item.setHidden(hidden)
            if not hidden and first_visible is None:
                first_visible = row
            if item is current and hidden:
                current_hidden = True

        if current_hidden and first_visible is not None:
            self.template_list.setCurrentRow(first_visible)

        visible_count = sum(
            not self.template_list.item(row).isHidden()
            for row in range(self.template_list.count())
        )
        self.no_results_label.setVisible(visible_count == 0)
        if needle:
            self.statusBar().showMessage(
                f"{visible_count} prompt types match '{query}'.", 2500
            )

    def _on_template_selected(self, current: QListWidgetItem, previous):
        if not current:
            return
        key = current.data(Qt.ItemDataRole.UserRole)
        self._load_template(key)

    def _load_template(self, key: str):
        tpl = TEMPLATES[key]
        self._current_template_key = key
        self._settings.setValue("template/current", key)
        self._preview_is_manual = False
        self.form_group.setText(f"{_template_group(key)} template")
        self.form_title.setText(tpl.label)
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
        self._empty_required_fields = self._required_empty_fields(tpl)
        # Preserve cursor position when re-rendering
        cursor_pos = self.preview.textCursor().position()
        self._preview_is_manual = False
        self._rendering_preview = True
        self.preview.setPlainText(text)
        self._rendering_preview = False
        cursor = self.preview.textCursor()
        cursor.setPosition(min(cursor_pos, len(text)))
        self.preview.setTextCursor(cursor)
        self._update_count()
        self._update_preview_state()
        self._update_form_hint()

    def _required_empty_fields(self, tpl: Template) -> list[str]:
        if not self._current_form:
            return []
        values = self._current_form.values()
        missing = []
        for field in tpl.fields:
            is_required_path = field.kind in {"path", "paths"} and not field.default
            is_required_text = field.key in {"task_id"}
            if is_required_path or is_required_text:
                if not str(values.get(field.key, "")).strip():
                    missing.append(field.label)
        return missing

    # ─── Actions ───

    def _copy_to_clipboard(self):
        text = self.preview.toPlainText()
        if not text.strip():
            self.statusBar().showMessage("Preview is empty. Nothing copied.", 4000)
            return
        QGuiApplication.clipboard().setText(text)
        detail = (
            f" Copied with placeholders for: {', '.join(self._empty_required_fields)}."
            if self._empty_required_fields
            else ""
        )
        self.copy_btn.setText("Copied")
        self._copy_reset_timer.start(1600)
        self.statusBar().showMessage(
            f"Copied {len(text)} characters to clipboard.{detail}", 5000
        )

    def _save_as_file(self):
        text = self.preview.toPlainText()
        if not text.strip():
            self.statusBar().showMessage("Nothing to save — preview is empty.", 4000)
            return
        suggested = "prompt.txt"
        if self._current_template_key:
            suggested = f"prompt-{self._current_template_key.replace('_', '-')}.txt"
        save_dir = self._settings.value(
            "files/lastSaveDir", str(Path.home()), type=str
        )
        path, _ = QFileDialog.getSaveFileName(
            self, "Save prompt as text file",
            os.path.join(save_dir, suggested),
            "Text files (*.txt);;All files (*.*)",
        )
        if path:
            try:
                Path(path).write_text(text, encoding="utf-8")
                self._settings.setValue("files/lastSaveDir", str(Path(path).parent))
                self.statusBar().showMessage(f"Saved to {path}", 5000)
            except OSError as exc:
                self.statusBar().showMessage(f"Save failed: {exc}", 6000)

    def _reset_form(self):
        if self._current_template_key:
            self._load_template(self._current_template_key)
            self.statusBar().showMessage("Form reset to defaults.", 3000)

    def _on_preview_text_changed(self):
        if not self._rendering_preview:
            self._preview_is_manual = True
        self._update_count()
        self._update_preview_state()

    def _toggle_preview_wrap(self, enabled: bool):
        mode = (
            QPlainTextEdit.LineWrapMode.WidgetWidth
            if enabled
            else QPlainTextEdit.LineWrapMode.NoWrap
        )
        self.preview.setLineWrapMode(mode)
        self._settings.setValue("preview/wrapLines", enabled)
        state = "enabled" if enabled else "disabled"
        self.statusBar().showMessage(f"Line wrap {state}.", 2000)

    def _restore_copy_button(self):
        self.copy_btn.setText("Copy")

    def _update_count(self):
        text = self.preview.toPlainText()
        lines = text.count("\n") + (1 if text else 0)
        self.count_label.setText(f"{lines} lines · {len(text)} chars")

    def _update_preview_state(self):
        if self._preview_is_manual:
            self.preview_state.setText("Edited")
            self.preview_state.setProperty("tone", "warning")
            self.preview_state.setToolTip(
                "Manual edits will be replaced when a form field changes or Reset is used."
            )
        elif self._empty_required_fields:
            self.preview_state.setText("Needs paths")
            self.preview_state.setProperty("tone", "warning")
            self.preview_state.setToolTip("Some path fields are still placeholders.")
        else:
            self.preview_state.setText("Live preview")
            self.preview_state.setProperty("tone", "ok")
            self.preview_state.setToolTip("Preview updates automatically as fields change.")
        self.preview_state.style().unpolish(self.preview_state)
        self.preview_state.style().polish(self.preview_state)

    def _update_form_hint(self):
        if self._empty_required_fields:
            fields = ", ".join(self._empty_required_fields)
            self.form_hint.setText(
                f"Placeholder output is active until these fields are filled: {fields}."
            )
            self.form_hint.setProperty("tone", "warning")
        else:
            self.form_hint.setText(
                "All required fields are filled. The preview is ready to copy or save."
            )
            self.form_hint.setProperty("tone", "ok")
        self.form_hint.style().unpolish(self.form_hint)
        self.form_hint.style().polish(self.form_hint)

    def closeEvent(self, event):
        self._settings.setValue("window/geometry", self.saveGeometry())
        self._settings.setValue("window/splitterState", self.splitter.saveState())
        super().closeEvent(event)
