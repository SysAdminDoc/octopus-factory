"""Refined Catppuccin Mocha QSS theme.

Palette reference: https://github.com/catppuccin/catppuccin
Applied via QApplication.setStyleSheet so every widget inherits.
"""

# ─── Catppuccin Mocha palette ─────────────────────────────────────────────

BASE       = "#1e1e2e"  # main background
MANTLE     = "#181825"  # darker bg (sidebar)
CRUST      = "#11111b"  # darkest bg
TEXT       = "#cdd6f4"  # primary text
SUBTEXT_1  = "#bac2de"
SUBTEXT_0  = "#a6adc8"
OVERLAY_2  = "#9399b2"
OVERLAY_1  = "#7f849c"
OVERLAY_0  = "#6c7086"
SURFACE_2  = "#585b70"
SURFACE_1  = "#45475a"
SURFACE_0  = "#313244"
BLUE       = "#89b4fa"
LAVENDER   = "#b4befe"
SAPPHIRE   = "#74c7ec"
SKY        = "#89dceb"
TEAL       = "#94e2d5"
GREEN      = "#a6e3a1"
YELLOW     = "#f9e2af"
PEACH      = "#fab387"
MAROON     = "#eba0ac"
RED        = "#f38ba8"
MAUVE      = "#cba6f7"
PINK       = "#f5c2e7"
FLAMINGO   = "#f2cdcd"
ROSEWATER  = "#f5e0dc"


def stylesheet() -> str:
    return f"""
QWidget {{
    background-color: {BASE};
    color: {TEXT};
    font-family: "Segoe UI", "SF Pro Text", "Inter", system-ui, sans-serif;
    font-size: 10pt;
}}

QMainWindow, QDialog {{
    background-color: {BASE};
}}

QSplitter::handle {{
    background-color: {MANTLE};
    width: 2px;
}}

QSplitter::handle:hover {{
    background-color: {SURFACE_1};
}}

QWidget#nav_panel {{
    background-color: {MANTLE};
    border-right: 1px solid {SURFACE_0};
}}

QWidget#content_panel {{
    background-color: {BASE};
}}

QWidget#form_row {{
    background-color: transparent;
}}

QGroupBox {{
    background-color: {MANTLE};
    border: 1px solid {SURFACE_0};
    border-radius: 8px;
    margin-top: 14px;
    padding: 14px 12px 12px 12px;
}}

QGroupBox::title {{
    subcontrol-origin: margin;
    subcontrol-position: top left;
    padding: 0 8px;
    color: {MAUVE};
    font-weight: 600;
}}

QLabel {{
    background: transparent;
    color: {TEXT};
}}

QLabel#help_text {{
    color: {SUBTEXT_0};
    font-size: 9pt;
    line-height: 135%;
}}

QLabel#section_header {{
    color: {TEXT};
    font-size: 16pt;
    font-weight: 700;
    padding: 0;
}}

QLabel#section_title {{
    color: {TEXT};
    font-size: 16pt;
    font-weight: 700;
    padding: 0;
}}

QLabel#section_kicker {{
    color: {TEAL};
    font-size: 8pt;
    font-weight: 700;
    letter-spacing: 0.04em;
    text-transform: uppercase;
}}

QLabel#app_title {{
    color: {TEXT};
    font-size: 17pt;
    font-weight: 750;
}}

QLabel#app_subtitle, QLabel#nav_footer {{
    color: {SUBTEXT_0};
    font-size: 9pt;
    line-height: 140%;
}}

QLabel#empty_state {{
    background-color: rgba(49, 50, 68, 0.58);
    border: 1px dashed {SURFACE_1};
    border-radius: 8px;
    color: {OVERLAY_2};
    font-size: 9pt;
    padding: 16px 10px;
}}

QLabel#field_label {{
    color: {SUBTEXT_1};
    font-size: 9.5pt;
    font-weight: 600;
    padding-top: 0;
}}

QLabel#inline_notice {{
    background-color: rgba(49, 50, 68, 0.72);
    border: 1px solid {SURFACE_0};
    border-radius: 8px;
    color: {SUBTEXT_1};
    font-size: 9pt;
    padding: 9px 11px;
}}

QLabel#inline_notice[tone="warning"] {{
    background-color: rgba(250, 179, 135, 0.10);
    border-color: rgba(250, 179, 135, 0.42);
    color: {YELLOW};
}}

QLabel#inline_notice[tone="ok"] {{
    background-color: rgba(148, 226, 213, 0.10);
    border-color: rgba(148, 226, 213, 0.35);
    color: {TEAL};
}}

QLabel#status_pill {{
    background-color: {SURFACE_0};
    border: 1px solid {SURFACE_1};
    border-radius: 10px;
    color: {SUBTEXT_1};
    font-size: 8pt;
    font-weight: 700;
    padding: 3px 9px;
}}

QLabel#status_pill[tone="warning"] {{
    background-color: rgba(249, 226, 175, 0.12);
    border-color: rgba(249, 226, 175, 0.42);
    color: {YELLOW};
}}

QLabel#status_pill[tone="ok"] {{
    background-color: rgba(166, 227, 161, 0.10);
    border-color: rgba(166, 227, 161, 0.36);
    color: {GREEN};
}}

QLabel#footer_count {{
    color: {OVERLAY_1};
    font-size: 9pt;
}}

QLineEdit, QPlainTextEdit, QTextEdit, QComboBox, QSpinBox {{
    background-color: {MANTLE};
    border: 1px solid {SURFACE_1};
    border-radius: 8px;
    padding: 8px 10px;
    color: {TEXT};
    selection-background-color: {MAUVE};
    selection-color: {CRUST};
}}

QLineEdit:focus, QPlainTextEdit:focus, QTextEdit:focus,
QComboBox:focus, QSpinBox:focus {{
    border: 1px solid {LAVENDER};
    background-color: {CRUST};
}}

QLineEdit:hover, QPlainTextEdit:hover, QTextEdit:hover,
QComboBox:hover, QSpinBox:hover {{
    border-color: {SURFACE_2};
}}

QLineEdit:disabled, QPlainTextEdit:disabled, QComboBox:disabled, QSpinBox:disabled {{
    background-color: {MANTLE};
    color: {OVERLAY_0};
}}

QPlainTextEdit#preview {{
    background-color: {CRUST};
    color: {TEXT};
    border: 1px solid {SURFACE_1};
    border-radius: 10px;
    font-family: "Cascadia Code", "JetBrains Mono", "Consolas", "Menlo", monospace;
    font-size: 10pt;
    padding: 14px;
    selection-background-color: {MAUVE};
    selection-color: {CRUST};
}}

QPlainTextEdit#preview:focus {{
    border-color: {LAVENDER};
}}

QComboBox::drop-down {{
    border: 0;
    width: 24px;
}}

QComboBox::down-arrow {{
    image: none;
    border-left: 5px solid transparent;
    border-right: 5px solid transparent;
    border-top: 6px solid {LAVENDER};
    margin-right: 8px;
}}

QComboBox QAbstractItemView {{
    background-color: {SURFACE_0};
    color: {TEXT};
    border: 1px solid {SURFACE_1};
    border-radius: 6px;
    selection-background-color: {MAUVE};
    selection-color: {CRUST};
    padding: 4px;
}}

QPushButton {{
    background-color: {SURFACE_0};
    color: {TEXT};
    border: 1px solid {SURFACE_1};
    border-radius: 8px;
    padding: 8px 16px;
    font-weight: 650;
}}

QPushButton:hover {{
    background-color: {SURFACE_1};
    border: 1px solid {SURFACE_2};
}}

QPushButton:pressed {{
    background-color: {MANTLE};
    padding-top: 9px;
    padding-bottom: 7px;
}}

QPushButton:focus {{
    border: 1px solid {LAVENDER};
}}

QPushButton#secondary {{
    background-color: {MANTLE};
    color: {SUBTEXT_1};
}}

QPushButton#secondary:hover {{
    background-color: {SURFACE_0};
    color: {TEXT};
}}

QPushButton#primary {{
    background-color: {LAVENDER};
    color: {CRUST};
    border: 1px solid {LAVENDER};
    font-weight: 750;
}}

QPushButton#primary:hover {{
    background-color: {BLUE};
    border-color: {BLUE};
}}

QPushButton#primary:pressed {{
    background-color: {MAUVE};
}}

QCheckBox {{
    color: {TEXT};
    spacing: 8px;
    padding: 6px 0;
}}

QCheckBox#compact_checkbox {{
    color: {SUBTEXT_0};
    font-size: 9pt;
    padding: 0;
}}

QCheckBox#compact_checkbox::indicator {{
    width: 15px;
    height: 15px;
    border-radius: 4px;
}}

QCheckBox::indicator {{
    width: 18px;
    height: 18px;
    border: 1px solid {SURFACE_2};
    border-radius: 5px;
    background-color: {MANTLE};
}}

QCheckBox::indicator:hover {{
    border: 1px solid {MAUVE};
}}

QCheckBox::indicator:checked {{
    background-color: {LAVENDER};
    border: 1px solid {LAVENDER};
    image: none;
}}

QCheckBox::indicator:checked::after {{
    color: {CRUST};
    content: "✓";
}}

QListWidget#template_list {{
    background-color: {MANTLE};
    border: 1px solid transparent;
    border-radius: 8px;
    padding: 2px;
    outline: 0;
}}

QListWidget#template_list::item {{
    padding: 8px 10px;
    border-radius: 8px;
    color: {SUBTEXT_1};
    margin: 2px 0;
}}

QListWidget#template_list::item:hover {{
    background-color: {SURFACE_0};
    color: {TEXT};
}}

QListWidget#template_list::item:selected {{
    background-color: {SURFACE_0};
    border: 1px solid {SURFACE_2};
    color: {TEXT};
    font-weight: 650;
}}

QScrollArea {{
    background-color: {BASE};
    border: 0;
}}

QScrollArea#panel {{
    background-color: {BASE};
    border: 0;
}}

QScrollBar:vertical {{
    background-color: {MANTLE};
    width: 10px;
    margin: 0;
    border: 0;
}}

QScrollBar::handle:vertical {{
    background-color: {SURFACE_1};
    min-height: 30px;
    border-radius: 5px;
}}

QScrollBar::handle:vertical:hover {{
    background-color: {SURFACE_2};
}}

QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{
    height: 0;
    border: 0;
}}

QScrollBar:horizontal {{
    background-color: {MANTLE};
    height: 10px;
    margin: 0;
    border: 0;
}}

QScrollBar::handle:horizontal {{
    background-color: {SURFACE_1};
    min-width: 30px;
    border-radius: 5px;
}}

QScrollBar::handle:horizontal:hover {{
    background-color: {SURFACE_2};
}}

QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {{
    width: 0;
    border: 0;
}}

QStatusBar {{
    background-color: {MANTLE};
    color: {SUBTEXT_1};
    border-top: 1px solid {SURFACE_0};
    padding: 2px 8px;
}}

QStatusBar::item {{
    border: 0;
}}

QToolTip {{
    background-color: {CRUST};
    color: {TEXT};
    border: 1px solid {MAUVE};
    border-radius: 4px;
    padding: 4px 8px;
}}
"""
