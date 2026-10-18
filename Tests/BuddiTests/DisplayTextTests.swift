//
//  DisplayTextTests.swift
//  BuddiTests
//

import XCTest
@testable import buddi

final class DisplayTextTests: XCTestCase {
    func testInjectedTagBlockIsRemoved() {
        let raw = "<browser_instruction># Claude in Chrome\ntext</browser_instruction>\nme sigue pidiendo password"
        XCTAssertEqual(DisplayText.clean(raw), "me sigue pidiendo password")
    }

    func testMarkdownIsStripped() {
        XCTAssertEqual(
            DisplayText.clean("# Resultado\n**Fase 1 completada.** Ver `config.json`"),
            "Resultado Fase 1 completada. Ver config.json"
        )
    }

    func testOnlyNoiseBecomesNil() {
        XCTAssertNil(DisplayText.clean("<system-reminder>x</system-reminder>"))
    }

    func testArithmeticSurvives() {
        XCTAssertEqual(DisplayText.clean("2 * 3 = 6"), "2 * 3 = 6")
    }

    func testMarkdownLinkKeepsLabel() {
        XCTAssertEqual(DisplayText.clean("Mira [el doc](https://x.com/a) aqui"), "Mira el doc aqui")
    }
}
