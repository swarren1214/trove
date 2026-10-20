import Testing
@testable import Trove

/// The readers that don't need a camera: license barcodes, passport lines, VINs and dates.
struct ReadingTests {
    @Test func readsALicenseBarcode() {
        let payload = """
        @
        \u{1E}
        ANSI 636014090002DL00410278ZC03190008DLDAQD1234567
        DCSLANE
        DACJORDAN
        DADRILEY
        DBD01082021
        DBB04121986
        DBA01082029
        DAJUT
        DCGUSA
        """
        let reading = AAMVA.parse(payload)
        #expect(reading?.number == "D1234567")
        #expect(reading?.name == "Jordan Riley Lane")
        #expect(reading?.expiresOn == "2029-01-08")
        #expect(reading?.issuedOn == "2021-01-08")
        #expect(reading?.birthDate == "1986-04-12")
        #expect(reading?.type == .driversLicense)
    }

    @Test func readsAPassportsMachineLines() {
        // ICAO 9303's specimen passport.
        let lines = [
            "UNITED STATES OF AMERICA",
            "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
            "L898902C36UTO7408122F1204159ZE184226B<<<<<10",
        ]
        let reading = MRZ.parse(lines)
        #expect(reading?.number == "L898902C3")
        #expect(reading?.name == "Anna Maria Eriksson")
        #expect(reading?.birthDate == "1974-08-12")
        #expect(reading?.type == .passport)
    }

    @Test func rejectsABadCheckDigit() {
        let lines = [
            "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
            "L898902C37UTO7408122F1204159ZE184226B<<<<<10",
        ]
        #expect(MRZ.parse(lines) == nil)
    }

    @Test func findsAVIN() {
        #expect(VIN.find(in: "VIN: 5TDGZRBH1MS048213 Model HIGHLANDER") == "5TDGZRBH1MS048213")
        #expect(VIN.find(in: "No vehicle here") == nil)
    }

    @Test func cleansDates() {
        #expect(Dates.clean("2027-03-14") == "2027-03-14")
        #expect(Dates.clean("2027-02-30") == nil)
        #expect(Dates.clean("") == nil)
    }

    @Test func expiryChips() {
        #expect(Attention.chip(days: 0) == "Today")
        #expect(Attention.chip(days: 5) == "5 days")
        #expect(Attention.chip(days: 42) == "6 wk")
        #expect(Attention.chip(days: 146) == "5 mo")
    }

    @Test func masksNumbers() {
        #expect(SecureValue.tail("D1234567") == "4567")
        #expect(SecureValue.masked("D1234567").hasSuffix("4567"))
        #expect(!SecureValue.masked("D1234567").contains("D123"))
    }
}
