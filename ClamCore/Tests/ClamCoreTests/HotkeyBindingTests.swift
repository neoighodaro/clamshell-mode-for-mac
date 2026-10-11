import Foundation
import Testing
@testable import ClamCore

@Test func bindingNeedsAtLeastOneModifier() {
    #expect(!HotkeyBinding(keyCode: 40, modifiers: [], keyName: "K").isValid)
    #expect(HotkeyBinding(keyCode: 40, modifiers: [.control], keyName: "K").isValid)
}

@Test func carbonModifiersUseCarbonBitValues() {
    // cmdKey 0x0100, shiftKey 0x0200, optionKey 0x0800, controlKey 0x1000.
    #expect(HotkeyBinding(keyCode: 0, modifiers: [.command], keyName: "A").carbonModifiers == 0x0100)
    #expect(HotkeyBinding(keyCode: 0, modifiers: [.shift], keyName: "A").carbonModifiers == 0x0200)
    #expect(HotkeyBinding(keyCode: 0, modifiers: [.option], keyName: "A").carbonModifiers == 0x0800)
    #expect(HotkeyBinding(keyCode: 0, modifiers: [.control], keyName: "A").carbonModifiers == 0x1000)
    #expect(HotkeyBinding(keyCode: 0, modifiers: [.command, .control], keyName: "A").carbonModifiers == 0x1100)
}

@Test func displayStringUsesStandardSymbolOrder() {
    let all = HotkeyBinding(keyCode: 40, modifiers: [.command, .shift, .option, .control], keyName: "K")
    #expect(all.displayString == "⌃⌥⇧⌘K")
    #expect(HotkeyBinding(keyCode: 40, modifiers: [.command], keyName: "K").displayString == "⌘K")
}

@Test func bindingRoundTripsThroughJSON() throws {
    let binding = HotkeyBinding(keyCode: 40, modifiers: [.control, .option], keyName: "K")
    let data = try JSONEncoder().encode(binding)
    #expect(try JSONDecoder().decode(HotkeyBinding.self, from: data) == binding)
}

@Test func shiftAndOptionAloneAreInvalid() {
    #expect(!HotkeyBinding(keyCode: 40, modifiers: [.shift], keyName: "K").isValid)
    #expect(!HotkeyBinding(keyCode: 40, modifiers: [.option], keyName: "K").isValid)
    #expect(!HotkeyBinding(keyCode: 40, modifiers: [.shift, .option], keyName: "K").isValid)
    #expect(HotkeyBinding(keyCode: 40, modifiers: [.command], keyName: "K").isValid)
    #expect(HotkeyBinding(keyCode: 40, modifiers: [.control, .shift], keyName: "K").isValid)
}

@Test func nonPrintingKeysHaveReadableNames() {
    #expect(HotkeyKeyNames.name(forKeyCode: 49) == "Space")
    #expect(HotkeyKeyNames.name(forKeyCode: 97) == "F6")
    #expect(HotkeyKeyNames.name(forKeyCode: 126) == "↑")
    #expect(HotkeyKeyNames.name(forKeyCode: 40) == nil)
}
