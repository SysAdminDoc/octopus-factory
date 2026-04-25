#!/usr/bin/env bats
# Prompt-builder GUI import and UI-state smoke checks.

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    PROMPT_BUILDER="$REPO_ROOT/tools/prompt-builder"
    PYTHON_BIN="$(command -v python3 || command -v python || true)"
    if [[ -z "$PYTHON_BIN" ]]; then
        skip "python not installed"
    fi
}

@test "prompt-builder: python modules compile" {
    run "$PYTHON_BIN" -m compileall "$PROMPT_BUILDER/prompt_builder"
    [ "$status" -eq 0 ]
}

@test "prompt-builder: offscreen UI smoke keeps diagnostics and navigation intact" {
    if ! "$PYTHON_BIN" -c 'import PyQt6' >/dev/null 2>&1; then
        skip "PyQt6 not installed"
    fi

    run env QT_QPA_PLATFORM=offscreen PYTHONPATH="$PROMPT_BUILDER" "$PYTHON_BIN" - <<'PY'
from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import QApplication

from prompt_builder.templates import TEMPLATES, list_templates
from prompt_builder.theme import stylesheet
from prompt_builder.window import FormBuilder, PromptBuilderWindow

app = QApplication([])
app.setStyleSheet(stylesheet())
window = PromptBuilderWindow()
assert window.template_list.count() == len(list_templates())
assert window.template_list.itemDelegate() is not None
assert window.template_list.horizontalScrollBarPolicy() == Qt.ScrollBarPolicy.ScrollBarAlwaysOff
window.search_edit.setText("pdf")
assert "found" in window.nav_count_label.text()
assert window.preview_notice.text()
assert window.copy_btn.property("tone") in {"ready", "warning"}

fields = TEMPLATES["pdf_redesign"].fields
assert window._is_required_field(fields[0])
assert not window._is_required_field(fields[1])

form = FormBuilder(TEMPLATES["pdf_redesign"], lambda: None)
form.apply_field_states({"pdf_path": ("required", "Choose a PDF.")})
assert form._diagnostics["pdf_path"].text() == "Choose a PDF."
assert not form._diagnostics["pdf_path"].isHidden()

window.preview.setPlainText(window.preview.toPlainText() + "\nmanual note")
assert window.preview_state.text() == "Edited"
assert window.preview_notice.property("tone") == "warning"
assert window.copy_btn.property("tone") == "warning"
assert window.regenerate_btn.text() == "Rebuild"
window.preview.clear()
assert not window.copy_btn.isEnabled()
assert not window.save_btn.isEnabled()
window.close()
PY
    [ "$status" -eq 0 ]
}
