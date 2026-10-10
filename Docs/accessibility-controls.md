# Accessibility controls

Every control in the dock, menu bar, main window, panel, settings and onboarding has one row here,
generated from the view code by `Scripts/accessibility_controls.py`. Dictation is the input for
somebody who cannot use a mouse, so each control must be reachable by Tab under Full Keyboard
Access, operable by Space or Return, and named for VoiceOver and Voice Control with its visible
text.

## Columns

- **Control** is `path#Kind#n`, the n-th constructor of that kind in the file. It is stable across
  edits that do not add or remove a control of that kind above it.
- **Accessible name from** is read from the constructor, its trailing closures and its modifier
  chain: `text "…"` for a literal title, `expression` for a title computed at run time, `label
  view` for a `label:` closure or a button whose content shows text, `accessibilityLabel` when one
  is attached to the control, or set later on the variable an AppKit control is held in, `hidden
  from accessibility` for a control kept only for its shortcut, `container label` for a field
  inside a `PageEditorField`, which names it with its own label, and `none found` when the source
  shows none. `--check` fails on `none found`, so a control VoiceOver would announce without a
  name cannot be added; the read is from the source, so the walk is still what confirms the name
  is spoken.
- **Keyboard and Voice Control** is `pass`, or the issue number of the defect found, recorded in
  `Scripts/accessibility_controls_status.json` after the control is walked with Full Keyboard
  Access and Voice Control on. `unchecked` means nobody has walked it yet.

## Keeping it current

```bash
python3 Scripts/accessibility_controls.py           # rewrite the table
python3 Scripts/accessibility_controls.py --check   # exit 1 if stale, a control is unnamed or a status is malformed
```

A status keyed to a control that no longer exists fails `--check`, so a removed control cannot
leave a stale pass behind.

## Table

<!-- accessibility-controls:begin -->
112 controls; 0 walked; 0 with no accessible name found in the source.

| Screen | Control | Kind | Accessible name from | Keyboard and Voice Control |
|---|---|---|---|---|
| App | `Sources/Uttrflow/AppDelegate.swift#NSPopUpButton#1` | NSPopUpButton | accessibilityLabel | unchecked |
| App menu | `Sources/Uttrflow/MainMenu.swift#NSMenuItem#1` | NSMenuItem | expression | unchecked |
| Dock | `Sources/Uttrflow/Dock/DockSetupView.swift#Button#1` | Button | label view | unchecked |
| Dock | `Sources/Uttrflow/Dock/DockView.swift#Button#1` | Button | expression | unchecked |
| Dock | `Sources/Uttrflow/Dock/DockView.swift#Button#2` | Button | expression | unchecked |
| Dock | `Sources/Uttrflow/Dock/DockView.swift#Button#3` | Button | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/AccountPageView.swift#Button#1` | Button | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/DictationReportSheet.swift#TextField#1` | TextField | text "Line \(index + 1)" | unchecked |
| Main window | `Sources/Uttrflow/Main/DictationReportSheet.swift#Button#1` | Button | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Main/DictionaryEditorView.swift#TextField#1` | TextField | container label | unchecked |
| Main window | `Sources/Uttrflow/Main/DictionaryEditorView.swift#TextField#2` | TextField | container label | unchecked |
| Main window | `Sources/Uttrflow/Main/DictionaryPageView.swift#Toggle#1` | Toggle | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/DictionaryPageView.swift#Button#1` | Button | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/DictionaryPageView.swift#Button#2` | Button | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Main/DictionaryPageView.swift#Button#3` | Button | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/DictionaryPageView.swift#Button#4` | Button | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/DictionaryPageView.swift#Button#5` | Button | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/DictionaryPageView.swift#Button#6` | Button | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/HistoryPageView.swift#Button#1` | Button | text " · \(notice.link.title)" | unchecked |
| Main window | `Sources/Uttrflow/Main/HistoryPageView.swift#TextField#1` | TextField | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/HistoryRailRow.swift#Menu#1` | Menu | text "Fix Word" | unchecked |
| Main window | `Sources/Uttrflow/Main/HistoryRailRow.swift#Menu#2` | Menu | text "What Changed" | unchecked |
| Main window | `Sources/Uttrflow/Main/HistoryRailRow.swift#Menu#3` | Menu | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/HistoryRailRow.swift#Button#1` | Button | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/HistoryRailRow.swift#Button#2` | Button | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Main/HistoryRailRow.swift#Button#3` | Button | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/HistoryRailRow.swift#Button#4` | Button | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Main/HomeActivityView.swift#Button#1` | Button | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/HomeActivityView.swift#Button#2` | Button | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/HomeActivityView.swift#Menu#1` | Menu | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Main/HomeActivityView.swift#Button#3` | Button | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/HomeHeroView.swift#Button#1` | Button | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Main/HomeHeroView.swift#Button#2` | Button | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/HomePageView.swift#Button#1` | Button | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Main/InsightsPageView.swift#Button#1` | Button | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/MainDialogs.swift#Button#1` | Button | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/MainDialogs.swift#Button#2` | Button | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/MainDialogs.swift#Button#3` | Button | hidden from accessibility | unchecked |
| Main window | `Sources/Uttrflow/Main/MainEmptyStateScene.swift#Button#1` | Button | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/MainPieces.swift#Button#1` | Button | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Main/MainPieces.swift#Button#2` | Button | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/MainPieces.swift#Button#3` | Button | text "Not now" | unchecked |
| Main window | `Sources/Uttrflow/Main/MainPieces.swift#Button#4` | Button | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/MainPieces.swift#Button#5` | Button | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Main/MainPieces.swift#Button#6` | Button | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/MainWindowView.swift#TextField#1` | TextField | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/MainWindowView.swift#Picker#1` | Picker | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/PageParts.swift#TextField#1` | TextField | expression | unchecked |
| Main window | `Sources/Uttrflow/Main/PageParts.swift#Button#1` | Button | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/PageParts.swift#Button#2` | Button | label view | unchecked |
| Main window | `Sources/Uttrflow/Main/PageParts.swift#Button#3` | Button | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Main/PageParts.swift#Picker#1` | Picker | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Main/SnippetsPageView.swift#TextField#1` | TextField | container label | unchecked |
| Main window | `Sources/Uttrflow/Sidebar/SidebarView.swift#Button#1` | Button | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Sidebar/SidebarView.swift#Button#2` | Button | accessibilityLabel | unchecked |
| Main window | `Sources/Uttrflow/Sidebar/SidebarView.swift#Button#3` | Button | accessibilityLabel | unchecked |
| Menu bar | `Sources/Uttrflow/MenuBar/MenuBarController.swift#NSMenuItem#1` | NSMenuItem | expression | unchecked |
| Menu bar | `Sources/Uttrflow/MenuBar/MenuBarController.swift#NSMenuItem#2` | NSMenuItem | expression | unchecked |
| Menu bar | `Sources/Uttrflow/MenuBar/MenuBarController.swift#Button#1` | Button | label view | unchecked |
| Menu bar | `Sources/Uttrflow/MenuBar/MenuBarController.swift#Button#2` | Button | expression | unchecked |
| Menu bar | `Sources/Uttrflow/MenuBar/MenuBarPopoverView.swift#Button#1` | Button | label view | unchecked |
| Menu bar | `Sources/Uttrflow/MenuBar/MenuBarPopoverView.swift#Button#2` | Button | accessibilityLabel | unchecked |
| Menu bar | `Sources/Uttrflow/MenuBar/MenuBarPopoverView.swift#Button#3` | Button | accessibilityLabel | unchecked |
| Menu bar | `Sources/Uttrflow/MenuBar/MenuBarPopoverView.swift#Button#4` | Button | expression | unchecked |
| Menu bar | `Sources/Uttrflow/MenuBar/MenuBarPopoverView.swift#Button#5` | Button | expression | unchecked |
| Menu bar | `Sources/Uttrflow/MenuBar/MenuBarPopoverView.swift#Button#6` | Button | accessibilityLabel | unchecked |
| Onboarding | `Sources/Uttrflow/Onboarding/OnboardingCelebration.swift#Button#1` | Button | label view | unchecked |
| Onboarding | `Sources/Uttrflow/Onboarding/OnboardingPieces.swift#Button#1` | Button | label view | unchecked |
| Onboarding | `Sources/Uttrflow/Onboarding/OnboardingView.swift#Button#1` | Button | expression | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelGlass.swift#Button#1` | Button | accessibilityLabel | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#1` | Button | accessibilityLabel | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#TextField#1` | TextField | accessibilityLabel | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#2` | Button | text "Rename…" | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#3` | Button | text "Delete…" | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#4` | Button | accessibilityLabel | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#5` | Button | text "Rename collection" | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#6` | Button | text "Delete collection" | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#7` | Button | expression | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#8` | Button | expression | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#9` | Button | label view | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#10` | Button | accessibilityLabel | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#11` | Button | text "Cancel" | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#12` | Button | expression | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#TextField#2` | TextField | expression | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#13` | Button | label view | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#14` | Button | accessibilityLabel | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#15` | Button | expression | unchecked |
| Panel | `Sources/Uttrflow/Panel/QuickPanelView.swift#Button#16` | Button | hidden from accessibility | unchecked |
| Settings | `Sources/Uttrflow/Settings/ApplicationPicker+System.swift#NSPopUpButton#1` | NSPopUpButton | accessibilityLabel | unchecked |
| Settings | `Sources/Uttrflow/Settings/ApplicationPicker+System.swift#NSPopUpButton#2` | NSPopUpButton | accessibilityLabel | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlStyles.swift#Button#1` | Button | label view | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlStyles.swift#Button#2` | Button | label view | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlStyles.swift#Menu#1` | Menu | label view | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlStyles.swift#Button#3` | Button | label view | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlStyles.swift#Button#4` | Button | accessibilityLabel | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlView.swift#Toggle#1` | Toggle | expression | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlView.swift#Toggle#2` | Toggle | expression | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlView.swift#Button#1` | Button | label view | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlView.swift#Button#2` | Button | expression | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlView.swift#Button#3` | Button | label view | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlView.swift#Menu#1` | Menu | accessibilityLabel | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlView.swift#Button#4` | Button | expression | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlView.swift#Button#5` | Button | text "Cancel" | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsControlView.swift#Button#6` | Button | label view | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsDiagnosticsView.swift#Button#1` | Button | expression | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsDiagnosticsView.swift#Button#2` | Button | text "Copy" | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsDiagnosticsView.swift#Button#3` | Button | expression | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsPageView.swift#TextField#1` | TextField | expression | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsPageView.swift#Button#1` | Button | accessibilityLabel | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsPageView.swift#Button#2` | Button | accessibilityLabel | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsPaneView.swift#Button#1` | Button | text "Open Keyboard Settings" | unchecked |
| Settings | `Sources/Uttrflow/Settings/SettingsPaneView.swift#Button#2` | Button | label view | unchecked |
<!-- accessibility-controls:end -->
