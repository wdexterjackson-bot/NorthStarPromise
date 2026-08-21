import Testing

@testable import NSPCore

/// Content/workflow half of the exhaustive-switch gate — see
/// `ExhaustiveSwitchTests.swift` for the rationale and the capture/timeline
/// half.
@Suite("Exhaustive enum switches — content and workflow")
struct ExhaustiveSwitchContentTests {

    @Test func test_noteBlockType_allCasesSwitchExhaustively() {
        for type in NoteBlockType.allCases {
            switch type {
            case .richText, .checklist, .decision, .action, .quote, .question, .code, .table,
                .sketch, .photo, .linkPreview, .file, .transcriptExcerpt:
                continue
            }
        }
    }

    @Test func test_blockPrivacy_allCasesSwitchExhaustively() {
        for value in BlockPrivacy.allCases {
            switch value {
            case .shared, .privateToAuthor:
                continue
            }
        }
    }

    @Test func test_mergeState_allCasesSwitchExhaustively() {
        let cases: [MergeState] = [
            .standalone, .proposedForRecap(diffID: "d"),
            .mergedIntoRecap(insightID: .generate(clock: SystemClock())),
        ]
        for value in cases {
            switch value {
            case .standalone, .proposedForRecap, .mergedIntoRecap:
                continue
            }
        }
    }

    @Test func test_insightLayer_allCasesSwitchExhaustively() {
        for layer in InsightLayer.allCases {
            switch layer {
            case .flashRecap, .executiveSummary, .detailedNotes, .chapter, .takeaway, .risk,
                .openQuestion:
                continue
            }
        }
    }

    @Test func test_claimKind_allCasesSwitchExhaustively() {
        for kind in ClaimKind.allCases {
            switch kind {
            case .said, .agreed, .aiSuggests:
                continue
            }
        }
    }

    @Test func test_approvalState_allCasesSwitchExhaustively() {
        for state in ApprovalState.allCases {
            switch state {
            case .draft, .edited, .approved, .locked:
                continue
            }
        }
    }

    @Test func test_processingPlane_allCasesSwitchExhaustively() {
        for plane in ProcessingPlane.allCases {
            switch plane {
            case .onDevice, .cloud:
                continue
            }
        }
    }

    @Test func test_actionStatus_allCasesSwitchExhaustively() {
        for status in ActionStatus.allCases {
            switch status {
            case .proposed, .confirmed, .sent, .inProgress, .done, .dismissed:
                continue
            }
        }
    }

    @Test func test_decisionStatus_allCasesSwitchExhaustively() {
        for status in DecisionStatus.allCases {
            switch status {
            case .proposed, .approved, .superseded:
                continue
            }
        }
    }

    @Test func test_scheduledRecordingStatus_allCasesSwitchExhaustively() {
        for status in ScheduledRecordingStatus.allCases {
            switch status {
            case .pending, .notified, .started, .completed, .skipped, .missed, .cancelled:
                continue
            }
        }
    }

    @Test func test_scheduledRecordingAlertStyle_allCasesSwitchExhaustively() {
        for style in ScheduledRecordingAlertStyle.allCases {
            switch style {
            case .sound, .vibrateOnly, .silent:
                continue
            }
        }
    }

    @Test func test_scheduledRecordingDecision_allCasesSwitchExhaustively() {
        let cases: [ScheduledRecordingDecision] = [
            .notYetDue, .shouldNotify, .shouldAutoStop, .shouldMarkMissed, .terminal,
        ]
        for value in cases {
            switch value {
            case .notYetDue, .shouldNotify, .shouldAutoStop, .shouldMarkMissed, .terminal:
                continue
            }
        }
    }

    @Test func test_resolvedValue_allCasesSwitchExhaustively() {
        let cases: [ResolvedValue<String>] = [.explicit("x"), .inferred("x"), .unresolved]
        for value in cases {
            switch value {
            case .explicit, .inferred, .unresolved:
                continue
            }
        }
    }

    @Test func test_consentMethod_allCasesSwitchExhaustively() {
        for method in ConsentMethod.allCases {
            switch method {
            case .verbalAnnouncement, .checklistConfirmed, .inviteDisclosure:
                continue
            }
        }
    }

    @Test func test_auditResult_allCasesSwitchExhaustively() {
        for result in AuditResult.allCases {
            switch result {
            case .success, .failure, .denied:
                continue
            }
        }
    }

    @Test func test_glossaryEntryOrigin_allCasesSwitchExhaustively() {
        for origin in GlossaryEntryOrigin.allCases {
            switch origin {
            case .userEntered, .learned:
                continue
            }
        }
    }

    @Test func test_shareRole_allCasesSwitchExhaustively() {
        for role in ShareRole.allCases {
            switch role {
            case .viewer, .commenter, .editor:
                continue
            }
        }
    }

    @Test func test_shareScope_allCasesSwitchExhaustively() {
        for scope in ShareScope.allCases {
            switch scope {
            case .fullRecap, .sectionOnly, .actionsOnly, .soundbite:
                continue
            }
        }
    }

    @Test func test_downloadPolicy_allCasesSwitchExhaustively() {
        for policy in DownloadPolicy.allCases {
            switch policy {
            case .allowed, .blocked:
                continue
            }
        }
    }
}
