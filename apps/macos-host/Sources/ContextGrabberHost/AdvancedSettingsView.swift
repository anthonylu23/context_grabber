import SwiftUI

struct AdvancedSettingsView: View {
  @ObservedObject var model: ContextGrabberModel

  var body: some View {
    Form {
      Section("Output Directory") {
        Text(model.outputDirectoryLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)

        HStack(spacing: 8) {
          Button(checkmarkMenuOptionLabel(
            valueLabel: "Default Output Directory",
            isSelected: model.usingDefaultOutputDirectory
          )) {
            model.useDefaultOutputDirectory()
          }
          Button(checkmarkMenuOptionLabel(
            valueLabel: "Custom Output Directory",
            isSelected: !model.usingDefaultOutputDirectory
          )) {
            model.chooseCustomOutputDirectory()
          }
        }
      }

      Section("Capture Output") {
        Picker("Clipboard Copy Mode", selection: Binding(
          get: { model.clipboardCopyMode },
          set: { model.setClipboardCopyModePreference($0) }
        )) {
          ForEach(ClipboardCopyMode.allCases, id: \.self) { mode in
            Text(clipboardCopyModeLabel(mode)).tag(mode)
          }
        }

        Picker("Output Format", selection: Binding(
          get: { model.outputFormatPreset },
          set: { model.setOutputFormatPresetPreference($0) }
        )) {
          ForEach(OutputFormatPreset.allCases, id: \.self) { preset in
            Text(outputFormatPresetLabel(preset)).tag(preset)
          }
        }

        Picker("Product Context Line", selection: Binding(
          get: { model.includeProductContextLine },
          set: { model.setIncludeProductContextLinePreference($0) }
        )) {
          Text("On").tag(true)
          Text("Off").tag(false)
        }
      }

      Section("Retention") {
        Picker("Retention Max Files", selection: Binding(
          get: { model.retentionMaxFileCount },
          set: { model.setRetentionMaxFileCountPreference($0) }
        )) {
          ForEach(retentionMaxFileCountOptions, id: \.self) { option in
            Text(retentionMaxFileCountLabel(option)).tag(option)
          }
        }

        Picker("Retention Max Age", selection: Binding(
          get: { model.retentionMaxAgeDays },
          set: { model.setRetentionMaxAgeDaysPreference($0) }
        )) {
          ForEach(retentionMaxAgeDaysOptions, id: \.self) { option in
            Text(retentionMaxAgeDaysLabel(option)).tag(option)
          }
        }
      }

      Section("Summarizing") {
        Picker("Mode", selection: Binding(
          get: { model.summarizationMode },
          set: { model.setSummarizationModePreference($0) }
        )) {
          ForEach(SummarizationMode.allCases, id: \.self) { mode in
            Text(summarizationModeLabel(mode)).tag(mode)
          }
        }

        Picker("LLM Provider", selection: Binding(
          get: { model.summarizationProvider?.rawValue ?? "none" },
          set: { rawValue in
            if rawValue == "none" {
              model.setSummarizationProviderPreference(nil)
            } else if let provider = SummarizationProvider(rawValue: rawValue) {
              model.setSummarizationProviderPreference(provider)
            }
          }
        )) {
          Text("Not Set").tag("none")
          ForEach(SummarizationProvider.allCases, id: \.rawValue) { provider in
            Text(summarizationProviderLabel(provider)).tag(provider.rawValue)
          }
        }

        let modelOptions = summarizationModelOptions(for: model.summarizationProvider)
        if modelOptions.isEmpty {
          Text("Select an LLM provider to choose a model.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Picker("LLM Model", selection: Binding(
            get: { model.summarizationModel ?? "auto" },
            set: { selected in
              if selected == "auto" {
                model.setSummarizationModelPreference(nil)
              } else {
                model.setSummarizationModelPreference(selected)
              }
            }
          )) {
            Text("Auto").tag("auto")
            ForEach(modelOptions, id: \.self) { option in
              Text(option).tag(option)
            }
          }
        }

        Picker("Summary Budget", selection: Binding(
          get: { model.summaryTokenBudget },
          set: { model.setSummaryTokenBudgetPreference($0) }
        )) {
          ForEach(summaryTokenBudgetOptions, id: \.self) { option in
            Text("\(option) tokens").tag(option)
          }
        }
      }

      Section("Capture Control") {
        Button(model.capturesPausedPlaceholder ? "Resume Captures" : "Pause Captures") {
          model.toggleCapturePausedPlaceholder()
        }
      }
    }
    .formStyle(.grouped)
    .padding(12)
    .frame(minWidth: 560, minHeight: 620)
  }
}
