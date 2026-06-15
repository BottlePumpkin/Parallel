import XCTest
@testable import Parallel

final class IssueReporterTests: XCTestCase {
    func test_builds_new_issue_url_against_canonical_repo() {
        let url = IssueReporter.newIssueURL(title: "Hello", body: "world", labels: [])
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/BottlePumpkin/Parallel/issues/new")
    }

    func test_title_and_body_are_percent_encoded() {
        let url = IssueReporter.newIssueURL(
            title: "crash with # and & on input",
            body: "first line\nsecond line",
            labels: []
        )
        let q = url.query ?? ""
        XCTAssertTrue(q.contains("title=crash%20with%20%23%20and%20%26%20on%20input"))
        XCTAssertTrue(q.contains("body=first%20line%0Asecond%20line"))
    }

    func test_korean_text_is_encoded() {
        let url = IssueReporter.newIssueURL(title: "버그", body: "한글 본문", labels: [])
        let q = url.query ?? ""
        XCTAssertTrue(q.contains("title=%EB%B2%84%EA%B7%B8"))
        XCTAssertTrue(q.contains("body=%ED%95%9C%EA%B8%80%20%EB%B3%B8%EB%AC%B8"))
    }

    func test_labels_are_joined_with_comma() {
        let url = IssueReporter.newIssueURL(
            title: "t", body: "b",
            labels: ["user-report", "needs-triage"]
        )
        let q = url.query ?? ""
        XCTAssertTrue(q.contains("labels=user-report%2Cneeds-triage"))
    }

    func test_empty_body_still_builds() {
        let url = IssueReporter.newIssueURL(title: "title only", body: "", labels: [])
        XCTAssertTrue((url.query ?? "").contains("body="))
    }

    func test_no_labels_omits_label_param() {
        let url = IssueReporter.newIssueURL(title: "t", body: "b", labels: [])
        XCTAssertFalse((url.query ?? "").contains("labels="))
    }
}
