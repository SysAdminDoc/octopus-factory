"""Main window for the prompt builder.

Layout (left to right):
- Templates list (left rail)
- Per-template form (middle column)
- Live prompt preview + copy button (right column)
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from PyQt6.QtCore import Qt, QSize, QSettings, QTimer, QRect
from PyQt6.QtGui import (
    QGuiApplication,
    QFont,
    QAction,
    QKeySequence,
    QColor,
    QPainter,
    QPen,
)
from PyQt6.QtWidgets import (
    QAbstractItemView,
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
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QScrollArea,
    QSpinBox,
    QStyledItemDelegate,
    QStyle,
    QSplitter,
    QStatusBar,
    QVBoxLayout,
    QWidget,
)

from .templates import TEMPLATES, Template, Field, list_templates
from .theme import (
    CRUST,
    MANTLE,
    SUBTEXT_0,
    SUBTEXT_1,
    SURFACE_0,
    SURFACE_1,
    SURFACE_2,
    TEAL,
    TEXT,
)


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


class TemplateListDelegate(QStyledItemDelegate):
    """Paint prompt templates as compact, structured navigation cards."""

    def sizeHint(self, option, index) -> QSize:
        return QSize(option.rect.width(), 70)

    def paint(self, painter: QPainter, option, index):
        painter.save()
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        selected = bool(option.state & QStyle.StateFlag.State_Selected)
        hovered = bool(option.state & QStyle.StateFlag.State_MouseOver)
        rect = option.rect.adjusted(4, 3, -4, -3)
        bg = QColor(SURFACE_0 if selected or hovered else MANTLE)
        border = QColor(SURFACE_2 if selected else SURFACE_1 if hovered else MANTLE)

        painter.setPen(QPen(border, 1))
        painter.setBrush(bg)
        painter.drawRoundedRect(rect, 9, 9)

        label = str(index.data(Qt.ItemDataRole.UserRole + 3) or "")
        group = str(index.data(Qt.ItemDataRole.UserRole + 1) or "")
        description = str(index.data(Qt.ItemDataRole.UserRole + 4) or "")

        title_font = QFont(option.font)
        title_font.setPointSize(10)
        title_font.setWeight(QFont.Weight.DemiBold if selected else QFont.Weight.Medium)
        meta_font = QFont(option.font)
        meta_font.setPointSize(8)
        chip_font = QFont(option.font)
        chip_font.setPointSize(7)
        chip_font.setWeight(QFont.Weight.Bold)

        x = rect.left() + 10
        y = rect.top() + 8
        w = rect.width() - 20

        painter.setFont(chip_font)
        chip_metrics = painter.fontMetrics()
        chip_w = chip_metrics.horizontalAdvance(group.upper()) + 18
        chip_rect = QRect(rect.right() - chip_w - 9, y - 1, chip_w, 18)
        painter.setPen(QPen(QColor(TEAL if selected else SURFACE_2), 1))
        painter.setBrush(QColor(CRUST if selected else SURFACE_0))
        painter.drawRoundedRect(chip_rect, 9, 9)
        painter.setPen(QColor(TEAL if selected else SUBTEXT_1))
        painter.drawText(
            chip_rect,
            Qt.AlignmentFlag.AlignCenter,
            group.upper(),
        )

        title_rect = QRect(x, y, max(40, w - chip_w - 18), 20)
        painter.setFont(title_font)
        painter.setPen(QColor(TEXT))
        painter.drawText(
            title_rect,
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter,
            painter.fontMetrics().elidedText(
                label,
                Qt.TextElideMode.ElideRight,
                title_rect.width(),
            ),
        )

        desc_rect = QRect(x, y + 27, w, 30)
        painter.setFont(meta_font)
        painter.setPen(QColor(SUBTEXT_0 if selected else SUBTEXT_1))
        painter.drawText(
            desc_rect,
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop,
            painter.fontMetrics().elidedText(
                description,
                Qt.TextElideMode.ElideRight,
                desc_rect.width(),
            ),
        )

        painter.restore()


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
        self._rows: dict[str, QWidget] = {}
        self._labels: dict[str, QLabel] = {}
        self._diagnostics: dict[str, QLabel] = {}
        self.container = QWidget()
        self.layout = QVBoxLayout(self.container)
        self.layout.setContentsMargins(4, 10, 8, 12)
        self.layout.setSpacing(12)
        self._build()

    def _build(self):
        for f in self.template.fields:
            row = QWidget()
            row.setObjectName("form_row")
            self._rows[f.key] = row
            row_layout = QVBoxLayout(row)
            row_layout.setContentsMargins(0, 0, 0, 0)
            row_layout.setSpacing(5)

            widget = self._make_widget(f)
            widget.setAccessibleName(f.label)
            if f.help:
                widget.setToolTip(f.help)
            self._widgets[f.key] = widget

            if f.kind != "checkbox":
                label = QLabel(f.label)
                label.setObjectName("field_label")
                label.setWordWrap(True)
                self._labels[f.key] = label
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
            diagnostic = QLabel("")
            diagnostic.setObjectName("field_diagnostic")
            diagnostic.setWordWrap(True)
            diagnostic.hide()
            self._diagnostics[f.key] = diagnostic
            row_layout.addWidget(diagnostic)
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
            w.setObjectName("option_checkbox")
            w.setText(f.label)
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

    def set_values(self, values: dict[str, Any]):
        for f in self.template.fields:
            if f.key not in values:
                continue

            w = self._widgets[f.key]
            value = values[f.key]
            if isinstance(w, PathEdit):
                w.edit.blockSignals(True)
                w.setText(str(value))
                w.edit.blockSignals(False)
            elif isinstance(w, PathsEdit):
                w.blockSignals(True)
                w.setPlainText(str(value))
                w.blockSignals(False)
            elif isinstance(w, QPlainTextEdit):
                w.blockSignals(True)
                w.setPlainText(str(value))
                w.blockSignals(False)
            elif isinstance(w, QLineEdit):
                w.blockSignals(True)
                w.setText(str(value))
                w.blockSignals(False)
            elif isinstance(w, QSpinBox):
                w.blockSignals(True)
                try:
                    w.setValue(int(value))
                except (TypeError, ValueError):
                    pass
                w.blockSignals(False)
            elif isinstance(w, QComboBox):
                w.blockSignals(True)
                text = str(value)
                if text in f.choices:
                    w.setCurrentText(text)
                w.blockSignals(False)
            elif isinstance(w, QCheckBox):
                w.blockSignals(True)
                w.setChecked(bool(value))
                w.blockSignals(False)

    def apply_field_states(self, states: dict[str, tuple[str, str]]):
        for field in self.template.fields:
            state, message = states.get(field.key, ("", ""))
            targets = [self._rows.get(field.key), self._labels.get(field.key)]
            widget = self._widgets.get(field.key)
            targets.append(widget)
            if isinstance(widget, PathEdit):
                targets.extend([widget.edit, widget.button])
            diagnostic = self._diagnostics.get(field.key)
            if diagnostic:
                diagnostic.setText(message)
                diagnostic.setVisible(bool(message))
                diagnostic.setProperty("fieldState", state)
                targets.append(diagnostic)

            for target in targets:
                if target is None:
                    continue
                target.setProperty("fieldState", state)
                target.style().unpolish(target)
                target.style().polish(target)

            if widget:
                widget.setAccessibleDescription(message)


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
        self._pending_form_changes = False
        self._empty_required_fields: list[str] = []
        self._form_warnings: list[str] = []
        self._field_diagnostics: dict[str, tuple[str, str]] = {}
        self._settings = QSettings("octopus-factory", "Prompt Builder")
        self._copy_reset_timer = QTimer(self)
        self._copy_reset_timer.setSingleShot(True)
        self._copy_reset_timer.timeout.connect(self._restore_copy_button)
        self._save_reset_timer = QTimer(self)
        self._save_reset_timer.setSingleShot(True)
        self._save_reset_timer.timeout.connect(self._restore_save_button)
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

        templates = list_templates()
        self.nav_count_label = QLabel(f"{len(templates)} prompt types")
        self.nav_count_label.setObjectName("nav_count")

        self.no_results_label = QLabel("No prompt types match this search.")
        self.no_results_label.setObjectName("empty_state")
        self.no_results_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.no_results_label.setWordWrap(True)
        self.no_results_label.hide()

        self.template_list = QListWidget()
        self.template_list.setObjectName("template_list")
        self.template_list.setMinimumWidth(220)
        self.template_list.setMaximumWidth(310)
        self.template_list.setMouseTracking(True)
        self.template_list.setHorizontalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAlwaysOff
        )
        self.template_list.setVerticalScrollMode(
            QAbstractItemView.ScrollMode.ScrollPerPixel
        )
        self.template_list.setItemDelegate(TemplateListDelegate(self.template_list))
        for tpl in templates:
            group = _template_group(tpl.key)
            item = QListWidgetItem(tpl.label)
            item.setData(Qt.ItemDataRole.UserRole, tpl.key)
            item.setData(Qt.ItemDataRole.UserRole + 1, group)
            item.setData(
                Qt.ItemDataRole.UserRole + 2,
                f"{tpl.label} {group} {tpl.description}".lower(),
            )
            item.setData(Qt.ItemDataRole.UserRole + 3, tpl.label)
            item.setData(Qt.ItemDataRole.UserRole + 4, tpl.description)
            item.setToolTip(tpl.description)
            item.setSizeHint(QSize(220, 70))
            self.template_list.addItem(item)
        self.template_list.currentItemChanged.connect(self._on_template_selected)

        nav_footer = QLabel(
            "Ctrl+F searches. Ctrl+Shift+C copies. Ctrl+S saves. "
            "F5 regenerates. Ctrl+R resets the current template."
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
        nav_layout.addWidget(self.nav_count_label)
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

        self.preview_notice = QLabel("")
        self.preview_notice.setObjectName("preview_notice")
        self.preview_notice.setWordWrap(True)
        self.preview_notice.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )

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

        self.reset_btn = QPushButton("Reset…")
        self.reset_btn.setObjectName("secondary")
        self.reset_btn.setMinimumHeight(40)
        self.reset_btn.setToolTip("No saved changes to reset.")
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
        preview_layout.addWidget(self.preview_notice)
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

        reset_action = QAction("Reset template", self)
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
            label = "prompt type" if visible_count == 1 else "prompt types"
            self.nav_count_label.setText(f"{visible_count} {label} found")
            self.statusBar().showMessage(
                f"{visible_count} prompt types match '{query}'.", 2500
            )
        else:
            label = "prompt type" if visible_count == 1 else "prompt types"
            self.nav_count_label.setText(f"{visible_count} {label}")

    def _on_template_selected(self, current: QListWidgetItem, previous):
        if not current:
            return
        key = current.data(Qt.ItemDataRole.UserRole)
        self._load_template(key)

    def _load_template(self, key: str, restore_saved: bool = True):
        tpl = TEMPLATES[key]
        self._current_template_key = key
        self._settings.setValue("template/current", key)
        self._preview_is_manual = False
        self.form_group.setText(f"{_template_group(key)} template")
        self.form_title.setText(tpl.label)
        self.form_description.setText(tpl.description)

        form = FormBuilder(tpl, on_change=self._on_form_changed)
        if restore_saved:
            form.set_values(self._saved_values_for(key))
        self._current_form = form
        self.form_scroll.setWidget(form.container)
        self._regenerate()
        self.statusBar().showMessage(f"Configuring: {tpl.label}")

    def _on_form_changed(self):
        self._save_current_form_values()
        if self._preview_is_manual:
            self._pending_form_changes = True
            if self._current_template_key:
                self._refresh_form_diagnostics(TEMPLATES[self._current_template_key])
            self._update_preview_state()
            self._update_form_hint()
            self.statusBar().showMessage(
                "Form changed. Manual preview edits are preserved until Regenerate.",
                4000,
            )
            return
        self._regenerate()

    def _template_values_key(self, key: str) -> str:
        return f"templates/{key}/values"

    def _saved_values_for(self, key: str) -> dict[str, Any]:
        raw = self._settings.value(self._template_values_key(key), "", type=str)
        if not raw:
            return {}
        try:
            value = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        return value if isinstance(value, dict) else {}

    def _default_values_for(self, tpl: Template) -> dict[str, Any]:
        values: dict[str, Any] = {}
        for field in tpl.fields:
            default = field.default
            if field.kind == "int":
                values[field.key] = int(default) if default else 0
            elif field.kind == "checkbox":
                values[field.key] = bool(default)
            elif field.kind == "choice":
                if default in field.choices:
                    values[field.key] = str(default)
                else:
                    values[field.key] = field.choices[0] if field.choices else ""
            else:
                values[field.key] = "" if default is None else str(default)
        return values

    def _normalized_field_value(self, field: Field, value: Any) -> Any:
        if field.kind == "int":
            try:
                return int(value)
            except (TypeError, ValueError):
                return 0
        if field.kind == "checkbox":
            return bool(value)
        return "" if value is None else str(value)

    def _changed_form_fields(self) -> list[str]:
        if not self._current_form or not self._current_template_key:
            return []
        tpl = TEMPLATES[self._current_template_key]
        values = self._current_form.values()
        defaults = self._default_values_for(tpl)
        changed: list[str] = []
        for field in tpl.fields:
            current = self._normalized_field_value(field, values.get(field.key))
            default = self._normalized_field_value(field, defaults.get(field.key))
            if current != default:
                changed.append(field.label)
        return changed

    def _save_current_form_values(self):
        if not self._current_form or not self._current_template_key:
            return
        self._settings.setValue(
            self._template_values_key(self._current_template_key),
            json.dumps(self._current_form.values()),
        )

    def _clear_current_form_values(self):
        if self._current_template_key:
            self._settings.remove(self._template_values_key(self._current_template_key))

    def _confirm_reset_form(self, tpl: Template, changed_fields: list[str]) -> bool:
        field_label = "field" if len(changed_fields) == 1 else "fields"
        details = ", ".join(changed_fields[:4])
        if len(changed_fields) > 4:
            details = f"{details}, and {len(changed_fields) - 4} more"

        box = QMessageBox(self)
        box.setIcon(QMessageBox.Icon.Warning)
        box.setWindowTitle("Reset template")
        box.setText(f"Reset {tpl.label} to defaults?")
        box.setInformativeText(
            f"This clears saved values for {len(changed_fields)} changed "
            f"{field_label}: {details}."
        )
        box.setDetailedText(
            "Manual preview edits are discarded, and future openings of this "
            "template will start from its defaults."
        )
        box.setStandardButtons(
            QMessageBox.StandardButton.Cancel | QMessageBox.StandardButton.Reset
        )
        box.setDefaultButton(QMessageBox.StandardButton.Cancel)
        return box.exec() == QMessageBox.StandardButton.Reset

    def _regenerate(self):
        if not self._current_form or not self._current_template_key:
            return
        tpl = TEMPLATES[self._current_template_key]
        try:
            text = tpl.render(self._current_form.values())
        except Exception as exc:
            text = f"# Render error: {exc}"
        self._refresh_form_diagnostics(tpl)
        # Preserve cursor position when re-rendering
        cursor_pos = self.preview.textCursor().position()
        self._preview_is_manual = False
        self._pending_form_changes = False
        self._rendering_preview = True
        self.preview.setPlainText(text)
        self._rendering_preview = False
        cursor = self.preview.textCursor()
        cursor.setPosition(min(cursor_pos, len(text)))
        self.preview.setTextCursor(cursor)
        self._update_count()
        self._update_preview_state()
        self._update_form_hint()

    def _refresh_form_diagnostics(self, tpl: Template):
        self._empty_required_fields = self._required_empty_fields(tpl)
        self._form_warnings = self._form_warnings_for(tpl)
        self._field_diagnostics = self._field_diagnostics_for(tpl)
        if self._current_form:
            self._current_form.apply_field_states(self._field_diagnostics)

    def _is_required_field(self, field: Field) -> bool:
        required_path_keys = {"repo", "repos", "pdf_path", "source_pdf"}
        return field.key in required_path_keys or field.key == "task_id"

    def _required_empty_fields(self, tpl: Template) -> list[str]:
        if not self._current_form:
            return []
        values = self._current_form.values()
        missing = []
        for field in tpl.fields:
            if self._is_required_field(field):
                if not str(values.get(field.key, "")).strip():
                    missing.append(field.label)
        return missing

    def _form_warnings_for(self, tpl: Template) -> list[str]:
        if not self._current_form:
            return []

        values = self._current_form.values()
        warnings: list[str] = []
        directory_keys = {"repo", "repos", "auto_discover"}
        pdf_keys = {"pdf_path", "source_pdf"}

        for field in tpl.fields:
            raw_value = str(values.get(field.key, "")).strip()
            if not raw_value:
                continue

            if field.key in directory_keys:
                paths = (
                    [line.strip() for line in raw_value.splitlines() if line.strip()]
                    if field.kind == "paths"
                    else [raw_value]
                )
                for item in paths:
                    path = Path(item).expanduser()
                    if not path.exists():
                        warnings.append(f"{field.label}: path not found")
                    elif not path.is_dir():
                        warnings.append(f"{field.label}: not a directory")
                    elif (
                        field.key in {"repo", "repos"}
                        and not (path / ".git").exists()
                    ):
                        warnings.append(f"{field.label}: no .git metadata")

            if field.key in pdf_keys:
                path = Path(raw_value).expanduser()
                if not path.exists():
                    warnings.append(f"{field.label}: file not found")
                elif not path.is_file():
                    warnings.append(f"{field.label}: not a file")
                elif path.suffix.lower() != ".pdf":
                    warnings.append(f"{field.label}: expected a .pdf file")

        if tpl.key == "ai_scrub" and values.get("mode") in {"apply", "push"}:
            warnings.append("AI Scrub apply/push rewrites history; dry-run first")

        return warnings[:3]

    def _field_diagnostics_for(self, tpl: Template) -> dict[str, tuple[str, str]]:
        if not self._current_form:
            return {}

        values = self._current_form.values()
        diagnostics: dict[str, tuple[str, str]] = {}
        directory_keys = {"repo", "repos", "auto_discover"}
        pdf_keys = {"pdf_path", "source_pdf"}

        for field in tpl.fields:
            raw_value = str(values.get(field.key, "")).strip()

            if self._is_required_field(field) and not raw_value:
                if field.kind == "paths":
                    message = "Add at least one project directory before using this prompt."
                elif field.kind == "path":
                    message = "Choose a path or keep the placeholder intentionally."
                else:
                    message = "Required before this prompt is ready."
                diagnostics[field.key] = ("required", message)
                continue

            if not raw_value:
                continue

            if field.key in directory_keys:
                paths = (
                    [line.strip() for line in raw_value.splitlines() if line.strip()]
                    if field.kind == "paths"
                    else [raw_value]
                )
                path_messages = []
                for item in paths:
                    path = Path(item).expanduser()
                    if not path.exists():
                        path_messages.append("path not found")
                    elif not path.is_dir():
                        path_messages.append("not a directory")
                    elif (
                        field.key in {"repo", "repos"}
                        and not (path / ".git").exists()
                    ):
                        path_messages.append("no .git metadata")
                if path_messages:
                    unique = ", ".join(dict.fromkeys(path_messages))
                    diagnostics[field.key] = ("warning", f"Review this value: {unique}.")

            if field.key in pdf_keys:
                path = Path(raw_value).expanduser()
                if not path.exists():
                    diagnostics[field.key] = ("warning", "File not found.")
                elif not path.is_file():
                    diagnostics[field.key] = ("warning", "Expected a file, not a directory.")
                elif path.suffix.lower() != ".pdf":
                    diagnostics[field.key] = ("warning", "Expected a .pdf file.")

        if tpl.key == "ai_scrub" and values.get("mode") in {"apply", "push"}:
            diagnostics["mode"] = (
                "warning",
                "History rewrite mode. Confirm dry-run output and backups before proceeding.",
            )

        return diagnostics

    # ─── Actions ───

    def _copy_to_clipboard(self):
        text = self.preview.toPlainText()
        if not text.strip():
            self.statusBar().showMessage("Preview is empty. Nothing copied.", 4000)
            return
        QGuiApplication.clipboard().setText(text)
        details = []
        if self._empty_required_fields:
            details.append(
                f"placeholders for: {', '.join(self._empty_required_fields)}"
            )
        if self._form_warnings:
            details.append("review warnings still present")
        detail = f" Copied with {'; '.join(details)}." if details else ""
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
                self.save_btn.setText("Saved")
                self._save_reset_timer.start(1600)
                self.statusBar().showMessage(f"Saved to {path}", 5000)
            except OSError as exc:
                self.statusBar().showMessage(f"Save failed: {exc}", 6000)

    def _reset_form(self):
        if not self._current_template_key:
            return
        key = self._current_template_key
        tpl = TEMPLATES[key]
        changed_fields = self._changed_form_fields()
        if not changed_fields:
            self.statusBar().showMessage("Already using template defaults.", 3000)
            self._update_action_states()
            return
        if not self._confirm_reset_form(tpl, changed_fields):
            self.statusBar().showMessage("Reset canceled.", 2500)
            return
        self._clear_current_form_values()
        self._load_template(key, restore_saved=False)
        self.statusBar().showMessage("Template values reset to defaults.", 3500)

    def _on_preview_text_changed(self):
        if not self._rendering_preview:
            self._preview_is_manual = True
            self._pending_form_changes = False
        self._update_count()
        self._update_preview_state()
        self._update_form_hint()

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

    def _restore_save_button(self):
        self.save_btn.setText("Save…")

    def _update_count(self):
        text = self.preview.toPlainText()
        lines = text.count("\n") + (1 if text else 0)
        self.count_label.setText(f"{lines} lines · {len(text)} chars")

    def _update_preview_state(self):
        self._copy_reset_timer.stop()
        self._save_reset_timer.stop()
        self._restore_copy_button()
        self._restore_save_button()

        if self._preview_is_manual and self._pending_form_changes:
            self.preview_state.setText("Unsynced")
            self.preview_state.setProperty("tone", "warning")
            self.preview_state.setToolTip(
                "Manual preview edits are preserved. Regenerate rebuilds from the form."
            )
        elif self._preview_is_manual:
            self.preview_state.setText("Edited")
            self.preview_state.setProperty("tone", "warning")
            self.preview_state.setToolTip(
                "Copy uses the edited preview. Regenerate restores generated text."
            )
        elif self._empty_required_fields:
            self.preview_state.setText("Needs paths")
            self.preview_state.setProperty("tone", "warning")
            self.preview_state.setToolTip("Some path fields are still placeholders.")
        elif self._form_warnings:
            self.preview_state.setText("Review")
            self.preview_state.setProperty("tone", "warning")
            self.preview_state.setToolTip("Review warnings before copying.")
        else:
            self.preview_state.setText("Live preview")
            self.preview_state.setProperty("tone", "ok")
            self.preview_state.setToolTip("Preview updates automatically as fields change.")
        self.preview_state.style().unpolish(self.preview_state)
        self.preview_state.style().polish(self.preview_state)
        self._update_preview_notice()
        self._update_action_states()

    def _update_preview_notice(self):
        if self._preview_is_manual and self._pending_form_changes:
            text = (
                "Form changes are waiting. Copy and Save use the edited preview; "
                "Regenerate rebuilds from the current form values."
            )
            tone = "warning"
        elif self._preview_is_manual:
            text = (
                "Manual edits are active. Copy and Save use exactly what is shown here."
            )
            tone = "warning"
        elif self._empty_required_fields:
            fields = ", ".join(self._empty_required_fields)
            text = f"Placeholder output is active until required fields are filled: {fields}."
            tone = "warning"
        elif self._form_warnings:
            text = f"Review before using this prompt: {'; '.join(self._form_warnings)}."
            tone = "warning"
        else:
            text = "Ready to copy or save. The preview updates automatically from the form."
            tone = "ok"

        self.preview_notice.setText(text)
        self.preview_notice.setProperty("tone", tone)
        self.preview_notice.style().unpolish(self.preview_notice)
        self.preview_notice.style().polish(self.preview_notice)

    def _update_action_states(self):
        has_text = bool(self.preview.toPlainText().strip())
        warning = bool(
            self._empty_required_fields
            or self._form_warnings
            or self._preview_is_manual
            or self._pending_form_changes
        )
        copy_tone = "warning" if warning else "ready"
        secondary_tone = "warning" if warning else ""

        self.copy_btn.setEnabled(has_text)
        self.save_btn.setEnabled(has_text)
        changed_fields = self._changed_form_fields()
        can_reset = bool(changed_fields)
        self.reset_btn.setEnabled(can_reset)
        self.copy_btn.setProperty("tone", copy_tone)
        self.save_btn.setProperty("tone", secondary_tone)
        self.regenerate_btn.setProperty("tone", secondary_tone)
        self.reset_btn.setProperty("tone", "warning" if can_reset else "")

        if self._preview_is_manual:
            self.regenerate_btn.setText("Rebuild")
            self.regenerate_btn.setToolTip(
                "Discard manual preview edits and rebuild from the current form values."
            )
        else:
            self.regenerate_btn.setText("Regenerate")
            self.regenerate_btn.setToolTip(
                "Restore the preview from the current form values."
            )

        if has_text and warning:
            self.copy_btn.setToolTip(
                "Copy the current preview. Review the readiness notice first."
            )
            self.save_btn.setToolTip(
                "Save the current preview. Review the readiness notice first."
            )
        elif has_text:
            self.copy_btn.setToolTip("Copy the current preview to the clipboard.")
            self.save_btn.setToolTip("Save the current preview as a text file.")
        else:
            self.copy_btn.setToolTip("Generate a prompt before copying.")
            self.save_btn.setToolTip("Generate a prompt before saving.")

        if can_reset:
            label = "field" if len(changed_fields) == 1 else "fields"
            self.reset_btn.setToolTip(
                f"Reset {len(changed_fields)} changed {label} to template defaults."
            )
        else:
            self.reset_btn.setToolTip("No saved changes to reset.")

        for widget in (
            self.copy_btn,
            self.save_btn,
            self.regenerate_btn,
            self.reset_btn,
        ):
            widget.style().unpolish(widget)
            widget.style().polish(widget)

    def _update_form_hint(self):
        if self._preview_is_manual and self._pending_form_changes:
            self.form_hint.setText(
                "Manual preview edits are preserved while form changes wait. "
                "Copy uses the edited text; Regenerate rebuilds from the form."
            )
            self.form_hint.setProperty("tone", "warning")
        elif self._preview_is_manual:
            self.form_hint.setText(
                "Manual preview edits are active. Copy uses the edited text; "
                "Regenerate discards edits and rebuilds from the form."
            )
            self.form_hint.setProperty("tone", "warning")
        elif self._empty_required_fields:
            fields = ", ".join(self._empty_required_fields)
            self.form_hint.setText(
                f"Placeholder output is active until these fields are filled: {fields}."
            )
            self.form_hint.setProperty("tone", "warning")
        elif self._form_warnings:
            warnings = "; ".join(self._form_warnings)
            self.form_hint.setText(
                f"Review before copying: {warnings}."
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
