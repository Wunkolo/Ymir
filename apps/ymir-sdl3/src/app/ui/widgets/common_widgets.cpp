#include "common_widgets.hpp"

#include <app/ui/fonts/IconsMaterialSymbols.h>

#include <imgui.h>

namespace app::ui::widgets {

void ExplanationTooltip(const char *explanation, float scale, bool sameLine) {
    if (sameLine) {
        ImGui::SameLine();
    }
    ImGui::TextDisabled(ICON_MS_HELP);
    if (ImGui::BeginItemTooltip()) {
        ImGui::PushTextWrapPos(450.0f * scale);
        ImGui::TextUnformatted(explanation);
        ImGui::PopTextWrapPos();
        ImGui::EndTooltip();
    }
}

} // namespace app::ui::widgets