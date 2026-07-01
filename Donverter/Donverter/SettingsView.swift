//
//  SettingsView.swift
//  Donverter
//
//  Dedicated native macOS Preferences/Settings window content.
//  Styled using macOS Grouped Form style for a native, clean Apple layout.
//

import SwiftUI

// MARK: - Color Hex Helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.deviceRGB)?.numberOfComponents else {
            return "#000000"
        }
        let nsColor = NSColor(self)
        let r = Float(nsColor.redComponent)
        let g = Float(nsColor.greenComponent)
        let b = Float(nsColor.blueComponent)
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}

// MARK: - Settings Window View

struct SettingsWindowView: View {
    @AppStorage("notchWidthExtension") private var widthExtension: Double = 90.0
    @AppStorage("dynamicIslandAlwaysExpanded") private var alwaysExpanded: Bool = false
    @AppStorage("dynamicIslandEnabled") private var isIslandEnabled: Bool = true
    @AppStorage("dynamicIslandBGColor") private var bgColorHex: String = "#000000"
    
    @AppStorage("dynamicIslandDismissBehavior") private var dismissBehavior: String = "timer"
    @AppStorage("dynamicIslandDismissSeconds") private var dismissSeconds: Double = 5.0
    @AppStorage("debugLogEnabled") private var isDebugLogEnabled: Bool = true
    
    @State private var widthText: String = ""

    var body: some View {
        Form {
            Section("General Settings") {
                Toggle("Enable Dynamic Island", isOn: $isIslandEnabled)
                    .toggleStyle(SwitchToggleStyle())
                
                LabeledContent("Console Output") {
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            isDebugLogEnabled.toggle()
                            if !isDebugLogEnabled {
                                DebugLogger.shared.clear()
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                                .font(.system(size: 11))
                            Text("Debug Log")
                                .font(.system(size: 12, weight: .medium))
                            Circle()
                                .fill(isDebugLogEnabled ? Color.green : Color.gray)
                                .frame(width: 7, height: 7)
                        }
                        .foregroundColor(isDebugLogEnabled ? .white : .white.opacity(0.45))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Section("Appearance & Behavior") {
                Picker("Display Mode", selection: $alwaysExpanded) {
                    Text("Hover to Expand").tag(false)
                    Text("Always Expanded").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .disabled(!isIslandEnabled)
                
                LabeledContent("Width Extension") {
                    HStack(spacing: 8) {
                        Slider(value: $widthExtension, in: 40.0...200.0, step: 1.0)
                            .frame(width: 140)
                            .onChange(of: widthExtension) { _, newValue in
                                widthText = String(Int(newValue))
                            }
                        
                        TextField("", text: $widthText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 50)
                            .multilineTextAlignment(.center)
                            .onSubmit {
                                if let val = Double(widthText) {
                                    widthExtension = min(max(val, 40.0), 200.0)
                                }
                                widthText = String(Int(widthExtension))
                            }
                        
                        Text("px")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(!isIslandEnabled)
                
                LabeledContent("Background Color") {
                    HStack(spacing: 8) {
                        let colorPresets = [
                            (hex: "#000000", name: "Pitch Black"),
                            (hex: "#1C1C1E", name: "Space Gray"),
                            (hex: "#2E3440", name: "Nordic Slate"),
                            (hex: "#FFFFFF", name: "Pure White"),
                            (hex: "#007AFF", name: "Deep Blue"),
                            (hex: "#5856D6", name: "Midnight Purple"),
                            (hex: "#FF3B30", name: "Coral Red")
                        ]
                        
                        ForEach(colorPresets, id: \.hex) { preset in
                            Button(action: {
                                bgColorHex = preset.hex
                            }) {
                                Circle()
                                    .fill(Color(hex: preset.hex))
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary.opacity(bgColorHex.uppercased() == preset.hex.uppercased() ? 0.8 : 0.25), lineWidth: bgColorHex.uppercased() == preset.hex.uppercased() ? 2.5 : 1)
                                    )
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                            }
                            .buttonStyle(.plain)
                            .help(preset.name)
                        }
                        
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: bgColorHex) },
                            set: { bgColorHex = $0.toHex() }
                        ))
                        .labelsHidden()
                        .frame(width: 28, height: 18)
                        .help("Custom Color...")
                    }
                }
                .disabled(!isIslandEnabled)
            }
            
            Section("Completion & Dismiss") {
                Picker("Dismiss Behavior", selection: $dismissBehavior) {
                    Text("Auto-dismiss").tag("timer")
                    Text("Keep Until Clicked").tag("manual")
                }
                .pickerStyle(SegmentedPickerStyle())
                .disabled(!isIslandEnabled)
                
                if dismissBehavior == "timer" {
                    Picker("Dismiss Timeout", selection: $dismissSeconds) {
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                        Text("30 seconds").tag(30.0)
                    }
                    .disabled(!isIslandEnabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 350)
        .preferredColorScheme(.dark)
        .onAppear {
            widthText = String(Int(widthExtension))
        }
    }
}

#Preview {
    SettingsWindowView()
}
