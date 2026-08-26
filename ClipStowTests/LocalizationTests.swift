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
            "en": (settings: "Settings", shortcut: "Global Shortcut", edit: "Edit", preview: "Preview", more: "Show More", folder: "Folder", selectFolder: "Select Folder", ascending: "Ascending", descending: "Descending"),
            "ko": (settings: "설정", shortcut: "호출 단축키", edit: "편집", preview: "미리보기", more: "더 보기", folder: "폴더", selectFolder: "폴더 선택", ascending: "오름차순", descending: "내림차순"),
            "ja": (settings: "設定", shortcut: "呼び出しショートカット", edit: "編集", preview: "プレビュー", more: "もっと見る", folder: "フォルダ", selectFolder: "フォルダを選択", ascending: "昇順", descending: "降順")
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
            XCTAssertEqual(
                bundle.localizedString(forKey: "폴더", value: nil, table: nil),
                expectedValue.folder
            )
            XCTAssertEqual(
                bundle.localizedString(forKey: "폴더 선택", value: nil, table: nil),
                expectedValue.selectFolder
            )
            XCTAssertEqual(
                bundle.localizedString(forKey: "오름차순", value: nil, table: nil),
                expectedValue.ascending
            )
            XCTAssertEqual(
                bundle.localizedString(forKey: "내림차순", value: nil, table: nil),
                expectedValue.descending
            )
        }
    }
}
