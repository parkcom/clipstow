import XCTest

final class LocalizationTests: XCTestCase {
    func testAppBundleProhibitsMultipleInstances() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "LSMultipleInstancesProhibited") as? Bool,
            true
        )
    }

    func testEnglishKoreanAndJapaneseResourcesContainCoreKeys() throws {
        let expectedValues = [
            "en": (settings: "Settings", shortcut: "Global Shortcut", edit: "Edit", preview: "Preview", more: "Show More"),
            "ko": (settings: "설정", shortcut: "호출 단축키", edit: "편집", preview: "미리보기", more: "더 보기"),
            "ja": (settings: "設定", shortcut: "呼び出しショートカット", edit: "編集", preview: "プレビュー", more: "もっと見る")
        ]

        for (language, expectedValue) in expectedValues {
            let path = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj"),
                "Missing \(language) localization bundle"
            )
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(
                bundle.localizedString(forKey: "설정", value: nil, table: nil),
                expectedValue.settings
            )
            XCTAssertEqual(
                bundle.localizedString(forKey: "호출 단축키", value: nil, table: nil),
                expectedValue.shortcut
            )
            XCTAssertEqual(
                bundle.localizedString(forKey: "편집", value: nil, table: nil),
                expectedValue.edit
            )
            XCTAssertEqual(
                bundle.localizedString(forKey: "미리보기", value: nil, table: nil),
                expectedValue.preview
            )
            XCTAssertEqual(
                bundle.localizedString(forKey: "더 보기", value: nil, table: nil),
                expectedValue.more
            )
        }
    }
}
