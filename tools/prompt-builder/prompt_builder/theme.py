"""Catppuccin Mocha QSS theme.

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
    background-color: {SURFACE_0};
    width: 2px;
}}

QSplitter::handle:hover {{
    background-color: {MAUVE};
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
    color: {OVERLAY_2};
    font-size: 9pt;
}}

QLabel#section_header {{
    color: {LAVENDER};
    font-size: 11pt;
    font-weight: 600;
    padding: 6px 0;
}}

QLabel#footer_count {{
    color: {OVERLAY_1};
    font-size: 9pt;
}}

QLineEdit, QPlainTextEdit, QTextEdit, QComboBox, QSpinBox {{
    background-color: {SURFACE_0};
    border: 1px solid {SURFACE_1};
    border-radius: 6px;
    padding: 6px 8px;
    color: {TEXT};
    selection-background-color: {MAUVE};
    selection-color: {CRUST};
}}

QLineEdit:focus, QPlainTextEdit:focus, QTextEdit:focus,
QComboBox:focus, QSpinBox:focus {{
    border: 1px solid {MAUVE};
}}

QLineEdit:disabled, QPlainTextEdit:disabled, QComboBox:disabled, QSpinBox:disabled {{
    background-color: {MANTLE};
    color: {OVERLAY_0};
}}

QPlainTextEdit#preview {{
    background-color: {CRUST};
    color: {TEXT};
    border: 1px solid {SURFACE_0};
    border-radius: 6px;
    font-family: "Cascadia Code", "JetBrains Mono", "Consolas", "Menlo", monospace;
    font-size: 10pt;
    padding: 12px;
    selection-background-color: {MAUVE};
    selection-color: {CRUST};
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
    background-color: {SURFACE_1};
    color: {TEXT};
    border: 1px solid {SURFACE_2};
    border-radius: 6px;
    padding: 7px 16px;
    font-weight: 500;
}}

QPushButton:hover {{
    background-color: {SURFACE_2};
    border: 1px solid {OVERLAY_0};
}}

QPushButton:pressed {{
    background-color: {SURFACE_0};
}}

QPushButton#primary {{
    background-color: {MAUVE};
    color: {CRUST};
    border: 1px solid {MAUVE};
    font-weight: 600;
}}

QPushButton#primary:hover {{
    background-color: {LAVENDER};
}}

QPushButton#primary:pressed {{
    background-color: {BLUE};
}}

QCheckBox {{
    color: {TEXT};
    spacing: 8px;
    padding: 2px 0;
}}

QCheckBox::indicator {{
    width: 16px;
    height: 16px;
    border: 1px solid {SURFACE_2};
    border-radius: 4px;
    background-color: {SURFACE_0};
}}

QCheckBox::indicator:hover {{
    border: 1px solid {MAUVE};
}}

QCheckBox::indicator:checked {{
    background-color: {MAUVE};
    border: 1px solid {MAUVE};
    image: none;
}}

QCheckBox::indicator:checked::after {{
    color: {CRUST};
    content: "✓";
}}

QListWidget {{
    background-color: {MANTLE};
    border: 1px solid {SURFACE_0};
    border-radius: 6px;
    padding: 4px;
    outline: 0;
}}

QListWidget::item {{
    padding: 8px 10px;
    border-radius: 4px;
    color: {TEXT};
}}

QListWidget::item:hover {{
    background-color: {SURFACE_0};
}}

QListWidget::item:selected {{
    background-color: {MAUVE};
    color: {CRUST};
    font-weight: 600;
}}

QScrollArea {{
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
