import Sentry
import SentryTestUtils
import XCTest

class SentryTransportAdapterTests: XCTestCase {
    
    private class Fixture {

        let transport1 = TestTransport()
        let transport2 = TestTransport()
        let options = Options()
        let faultyAttachment = Attachment(path: "")
        let attachment = Attachment(data: Data(), filename: "test.txt")
        
        var sut: SentryTransportAdapter {
            return SentryTransportAdapter(transports: [transport1, transport2], options: options)
        }
    }

    private var fixture: Fixture!
    private var sut: SentryTransportAdapter!

    override func setUp() {
        super.setUp()
        
        SentryDependencyContainer.sharedInstance().dateProvider = TestCurrentDateProvider()
        
        fixture = Fixture()
        sut = fixture.sut
    }
    
    override func tearDown() {
        super.tearDown()
        clearTestState()
    }
    
    func testSendEventWithSession_SendsCorrectEnvelope() throws {
        let session = SentrySession(releaseName: "1.0.1", distinctId: "some-id")
        let event = TestData.event
        sut.send(event, session: session, attachments: [fixture.attachment])
        
        let expectedEnvelope = SentryEnvelope(id: event.eventId, items: [
            SentryEnvelopeItem(event: event),
            SentryEnvelopeItem(attachment: fixture.attachment, maxAttachmentSize: fixture.options.maxAttachmentSize)!,
            SentryEnvelopeItem(session: session)
        ])
        
        try assertSentEnvelope(expected: expectedEnvelope)
    }

    func testSendFaultyAttachment_FaultyAttachmentGetsDropped() throws {
        let event = TestData.event
        sut.send(event: event, traceContext: nil, attachments: [fixture.faultyAttachment, fixture.attachment])
        
        let expectedEnvelope = SentryEnvelope(id: event.eventId, items: [
            SentryEnvelopeItem(event: event),
            SentryEnvelopeItem(attachment: fixture.attachment, maxAttachmentSize: fixture.options.maxAttachmentSize)!
        ])
        
        try assertSentEnvelope(expected: expectedEnvelope)
    }
    
    func testSendUserFeedback_SendsUserFeedbackEnvelope() throws {
        let userFeedback = TestData.userFeedback
        sut.send(userFeedback: userFeedback)
        
        let expectedEnvelope = SentryEnvelope(userFeedback: userFeedback)
        
        try assertSentEnvelope(expected: expectedEnvelope)
    }
    
    func testSaveEvent_StoresCorrectEnvelope() throws {
        let event = TestData.event
        sut.save(event, traceContext: nil)
        
        let expectedEnvelope = SentryEnvelope(id: event.eventId, items: [
            SentryEnvelopeItem(event: event)
        ])
        
        try assertStoredEnvelope(expected: expectedEnvelope)
    }
    
    private func assertStoredEnvelope(expected: SentryEnvelope) throws {
        XCTAssertEqual(self.fixture.transport1.storedEnvelopes.count, 1)
        XCTAssertEqual(self.fixture.transport2.storedEnvelopes.count, 1)
        
        let actual = try XCTUnwrap(fixture.transport1.storedEnvelopes.first)
        try assertEnvelope(expected: expected, actual: actual)
    }
    
    private func assertSentEnvelope(expected: SentryEnvelope) throws {
        XCTAssertEqual(self.fixture.transport1.sentEnvelopes.count, 1)
        XCTAssertEqual(self.fixture.transport2.sentEnvelopes.count, 1)
        
        let actual = try XCTUnwrap(fixture.transport1.sentEnvelopes.first)
        
        try assertEnvelope(expected: expected, actual: actual)
    }
    
    private func assertEnvelope(expected: SentryEnvelope, actual: SentryEnvelope) throws {
        XCTAssertEqual(expected.header.eventId, actual.header.eventId)
        XCTAssertEqual(expected.header.sdkInfo, actual.header.sdkInfo)
        XCTAssertEqual(expected.items.count, actual.items.count)
        
        expected.items.forEach { expectedItem in
            let expectedHeader = expectedItem.header
            let containsHeader = actual.items.contains { _ in
                expectedHeader.type == expectedItem.header.type &&
                expectedHeader.contentType == expectedItem.header.contentType
            }
            
            XCTAssertTrue(containsHeader, "Envelope doesn't contain item with type:\(expectedHeader.type).")

            let containsData = actual.items.contains { actualItem in
                actualItem.data == expectedItem.data
            }
            
            XCTAssertTrue(containsData, "Envelope data with type:\(expectedHeader.type) doesn't match.")
        }
        
        let actualSerialized = try XCTUnwrap(SentrySerialization.data(with: actual))
        XCTAssertEqual(try XCTUnwrap(SentrySerialization.data(with: expected)), actualSerialized)
    
    }
}
