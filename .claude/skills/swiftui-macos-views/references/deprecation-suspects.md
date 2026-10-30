# Deprecation suspects

Patterns LLMs write out of habit that the SDK has replaced or soft-deprecated. This is a list of things to **check**, not a source of truth: run the regex through `.claude/skills/apple-api-check/scripts/sdk-api.sh -m SwiftUI '<regex>'` and trust what the installed SDK says, including any new replacement it names. `deprecated: 100000.0` means soft-deprecated: no warning yet, but don't write it in new code.

Add a row whenever you meet a new habit-driven API in review. Remove a row only if the SDK no longer flags it.

| Habit | Usual replacement (verify) | Regex to check |
|---|---|---|
| `.foregroundColor(_:)` | `.foregroundStyle(_:)` | `func foregroundColor` |
| `.cornerRadius(_:)` | `.clipShape(.rect(cornerRadius:))` | `func cornerRadius\(` |
| `.accentColor(_:)` | `.tint(_:)` or the asset accent colour | `func accentColor\(` |
| `NavigationView` | `NavigationStack` / `NavigationSplitView` | `struct NavigationView<` |
| `.onChange(of:perform:)` with one-value closure | two-parameter or zero-parameter closure | `func onChange<V>\(of value: V, perform` |
| `.overlay(view, alignment:)`, `.background(view, alignment:)` | closure forms `overlay(alignment:content:)` | `func overlay<Overlay>\(_ overlay: Overlay, alignment` |
| `.alert(isPresented:content:)` with `Alert(...)` | `.alert(_:isPresented:actions:message:)` | `func alert\(isPresented` |
| `.actionSheet` | `.confirmationDialog` | `func actionSheet` |
| `.tabItem` | `Tab(...)` initializers | `func tabItem` |
| `.edgesIgnoringSafeArea` | `.ignoresSafeArea` | `func edgesIgnoringSafeArea` |
| `Text("a") + Text("b")` | string interpolation inside one `Text` | `static func \+ \(lhs: SwiftUI[A-Za-z.:]*Text,` |
| `.animation(_:)` without `value:` | `.animation(_:value:)` or `withAnimation` | `func animation\(_ animation` |
| `.onTapGesture(count:coordinateSpace:perform:)` old coordinate space | overload taking a `CoordinateSpaceProtocol` | `func onTapGesture\(count` |
| `PreviewProvider` structs | `#Preview` macro | `protocol PreviewProvider` |
| `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject` | `@Observable`, `@State`, plain property / `@Bindable`, `@Environment(Type.self)` | `-m Observation 'macro Observable'` (check target) |
| `GeometryReader` just to read a size | `onGeometryChange`, `containerRelativeFrame` | `func onGeometryChange` |
| `NSApp.sendAction(Selector(("showSettingsWindow:")))` | `@Environment(\.openSettings)` / `SettingsLink` | `struct OpenSettingsAction` |
| `DispatchQueue.main.async` in views | `Task { }` on the main actor, `.task { }` | not an SDK deprecation; a concurrency-style smell |
| `.onAppear { Task { ... } }` | `.task { ... }` (cancelled on disappear) | not deprecated; lifecycle correctness |
| UIKit names in Mac code (`UIColor`, `UIImage`, `.navigationBarTitle`) | `Color`/`NSColor`, `Image`/`NSImage`, `.navigationTitle` | `-m AppKit` / `-m SwiftUI` |
