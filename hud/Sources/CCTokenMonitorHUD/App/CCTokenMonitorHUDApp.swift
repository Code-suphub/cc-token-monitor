import SwiftUI
import Charts

@main
struct CCTokenMonitorHUDApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 140, height: 100)
    }
}

struct ContentView: View {
    @StateObject private var dataService = DataService()
    @State private var showDetail = false

    var body: some View {
        VStack(spacing: 8) {
            // Tokens 行
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 10))
                Text(dataService.todayStats?.formattedTokens ?? "--")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text("tokens")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }

            // Cost 行
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 10))
                Text("$" + (dataService.todayStats?.formattedCost ?? "--"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.green)
                    .lineLimit(1)
                Text("cost")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }

            // 环比
            if let change = dataService.dayOverDayChange() {
                HStack(spacing: 2) {
                    Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8))
                    Text("\(abs(change * 100), specifier: "%.0f")%")
                        .font(.system(size: 8))
                }
                .foregroundColor(change >= 0 ? .red : .green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 140, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .onTapGesture {
            showDetail.toggle()
        }
        .sheet(isPresented: $showDetail) {
            DetailView(dataService: dataService)
        }
        .onAppear {
            dataService.startTimer(interval: 30)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let window = NSApplication.shared.windows.first else { return }

                if let screen = NSScreen.main ?? NSScreen.screens.first {
                    let frame = screen.visibleFrame
                    let x = frame.origin.x + frame.width / 2 - 70
                    let y = frame.origin.y + frame.height / 2 - 50
                    window.setFrameOrigin(NSPoint(x: x, y: y))
                }

                window.level = .floating
                window.makeKeyAndOrderFront(nil)
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
