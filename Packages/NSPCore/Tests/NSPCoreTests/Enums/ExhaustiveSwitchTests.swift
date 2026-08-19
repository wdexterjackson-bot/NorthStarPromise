import Testing

@testable import NSPCore

/// One switch per enum in the domain model, with no `default:` branch. If a
/// case is ever added without updating the matching switch here, this file
/// fails to compile — that compiler enforcement *is* the "100% of enums
/// exhaustively switched" gate from NSP-006's acceptance criteria.
@Suite("Exhaustive enum switches")
struct ExhaustiveSwitchTests {

    @Test func test_captureMode_allCasesSwitchExhaustively() {
        for mode in CaptureMode.allCases {
            switch mode {
            case .watch, .phone, .pad, .import, .onlineAssistant, .dialer:
                continue
            }
        }
    }

    @Test func test_processingMode_allCasesSwitchExhaustively() {
        for mode in ProcessingMode.allCases {
            switch mode {
            case .localOnly, .onDevicePreferred, .cloudAllowed:
                continue
            }
        }
    }

    @Test func test_availability_allCasesSwitchExhaustively() {
        let ref = SegmentRef(
            segmentID: .generate(clock: SystemClock()), deviceID: .generate(clock: SystemClock()),
            sequence: 0)
        let cases: [Availability] = [.complete, .partial(missing: [ref]), .recoverable, .failed]
        for value in cases {
            switch value {
            case .complete, .partial, .recoverable, .failed:
                continue
            }
        }
    }

    @Test func test_transferState_allCasesSwitchExhaustively() {
        let cases: [TransferState] = [
            .local, .queued, .inFlight, .receivedUnverified, .verified, .reclaimed,
            .failed(reason: "x"),
        ]
        for value in cases {
            switch value {
            case .local, .queued, .inFlight, .receivedUnverified, .verified, .reclaimed, .failed:
                continue
            }
        }
    }

    @Test func test_audioCodec_allCasesSwitchExhaustively() {
        for codec in AudioCodec.allCases {
            switch codec {
            case .aacLC, .heAAC:
                continue
            }
        }
    }

    @Test func test_meetingState_allCasesSwitchExhaustively() {
        let cases: [MeetingState] = [
            .ready, .arming, .recording, .paused, .interrupted, .finalizing, .processing,
            .readyForReview, .approved, .edited, .shared, .archived, .deleted, .restored,
            .purged, .recoverable, .savedRaw, .partialFailure, .failed(reason: "x"),
        ]
        for value in cases {
            switch value {
            case .ready, .arming, .recording, .paused, .interrupted, .finalizing, .processing,
                .readyForReview, .approved, .edited, .shared, .archived, .deleted, .restored,
                .purged, .recoverable, .savedRaw, .partialFailure, .failed:
                continue
            }
        }
    }

    @Test func test_interruptionCause_allCasesSwitchExhaustively() {
        for cause in InterruptionCause.allCases {
            switch cause {
            case .phoneCall, .siri, .otherApp, .systemAlert:
                continue
            }
        }
    }

    @Test func test_audioRouteEndpoint_allCasesSwitchExhaustively() {
        for endpoint in AudioRouteEndpoint.allCases {
            switch endpoint {
            case .builtInMic, .bluetooth, .airpods, .wiredHeadset, .other:
                continue
            }
        }
    }

    @Test func test_markerKind_allCasesSwitchExhaustively() {
        for kind in MarkerKind.allCases {
            switch kind {
            case .important, .actionItem, .question:
                continue
            }
        }
    }

    @Test func test_levelWarningKind_allCasesSwitchExhaustively() {
        for kind in LevelWarningKind.allCases {
            switch kind {
            case .silence, .clipping, .inputLoss, .lowLevel:
                continue
            }
        }
    }

    @Test func test_thermalState_allCasesSwitchExhaustively() {
        for state in ThermalState.allCases {
            switch state {
            case .nominal, .fair, .serious, .critical:
                continue
            }
        }
    }

    @Test func test_sealedStopReason_allCasesSwitchExhaustively() {
        for reason in SealedStopReason.allCases {
            switch reason {
            case .thermalCritical, .batteryCritical, .storageCritical:
                continue
            }
        }
    }

    @Test func test_timelineEventType_allCasesSwitchExhaustively() {
        let cases: [TimelineEventType] = [
            .start, .pause, .resume,
            .interruptionBegan(cause: .phoneCall), .interruptionEnded,
            .routeChange(from: .builtInMic, to: .airpods),
            .marker(kind: .important), .levelWarning(kind: .silence),
            .thermal(state: .fair), .batteryWarning, .storageWarning,
            .sealedStop(reason: .thermalCritical), .stop,
        ]
        for value in cases {
            switch value {
            case .start, .pause, .resume, .interruptionBegan, .interruptionEnded,
                .routeChange, .marker, .levelWarning, .thermal, .batteryWarning,
                .storageWarning, .sealedStop, .stop:
                continue
            }
        }
    }

    @Test func test_editState_allCasesSwitchExhaustively() {
        let cases: [EditState] = [.machine, .userEdited(revisionOf: 1), .userConfirmed]
        for value in cases {
            switch value {
            case .machine, .userEdited, .userConfirmed:
                continue
            }
        }
    }

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
