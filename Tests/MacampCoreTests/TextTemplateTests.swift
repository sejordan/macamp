import Testing
@testable import MacampCore

private func values(_ change: (inout TemplateValues) -> Void = { _ in }) -> TemplateValues {
    var v = TemplateValues()
    v.title = "Low Tide Radio"; v.artist = "Night Ferry"; v.album = "Harbor"
    v.fileName = "03 low tide.flac"
    v.index = 3; v.count = 5
    v.duration = 227; v.elapsed = 84
    v.codec = "FLAC"; v.sampleRate = 44100; v.bitrate = 912_000; v.channels = 2
    v.state = "playing"
    change(&v)
    return v
}

@Test func formatTimeUnpaddedAndPadded() {
    #expect(formatTime(84, pad: false) == "1:24")
    #expect(formatTime(84, pad: true) == "01:24")
    #expect(formatTime(nil, pad: false) == "0:00")
    #expect(formatTime(nil, pad: true) == "00:00")
    #expect(formatTime(3723, pad: false) == "1:02:03")
    #expect(formatTime(-5, pad: false) == "0:00")
    #expect(formatTime(.nan, pad: false) == "0:00")
}

@Test func basicTokens() {
    let v = values()
    #expect(TextTemplate("{title}").render(v) == "Low Tide Radio")
    #expect(TextTemplate("{artist}").render(v) == "Night Ferry")
    #expect(TextTemplate("{album}").render(v) == "Harbor")
    #expect(TextTemplate("{index}. {display}").render(v) == "3. Night Ferry - Low Tide Radio")
    #expect(TextTemplate("{index}/{count}").render(v) == "3/5")
    #expect(TextTemplate("{state}").render(v) == "playing")
}

@Test func timeTokens() {
    let v = values()
    #expect(TextTemplate("{elapsed}").render(v) == "1:24")
    #expect(TextTemplate("{elapsed:pad}").render(v) == "01:24")
    #expect(TextTemplate("{duration}").render(v) == "3:47")
    #expect(TextTemplate("{remaining}").render(v) == "-2:23")
    #expect(TextTemplate("{time:pad}").render(v) == "01:24")
    #expect(TextTemplate("{time:pad}").render(values { $0.showRemaining = true }) == "-02:23")
    #expect(TextTemplate("{duration}").render(values { $0.duration = nil }) == "")
    #expect(TextTemplate("{elapsed}").render(values { $0.elapsed = nil }) == "0:00")
}

@Test func formatTokens() {
    let v = values()
    #expect(TextTemplate("{codec} · {sampleRate} · {bitrate} · {channels}").render(v)
            == "FLAC · 44.1 kHz · 912 kbps · stereo")
    #expect(TextTemplate("{sampleRate}").render(values { $0.sampleRate = 48000 }) == "48 kHz")
    #expect(TextTemplate("{channels}").render(values { $0.channels = 1 }) == "mono")
    #expect(TextTemplate("{channels}").render(values { $0.channels = 6 }) == "6 ch")
    #expect(TextTemplate("{codec}{sampleRate}{bitrate}{channels}").render(TemplateValues()) == "")
}

@Test func displayNeverLeavesDanglingSeparator() {
    #expect(TextTemplate("{display}").render(values { $0.artist = nil }) == "Low Tide Radio")
    #expect(TextTemplate("{display}").render(values { $0.artist = "" }) == "Low Tide Radio")
    #expect(TextTemplate("{display}").render(values { $0.artist = nil; $0.title = nil }) == "03 low tide")
    #expect(TextTemplate("{title}").render(values { $0.title = nil }) == "03 low tide")
    #expect(TextTemplate("{display}").render(TemplateValues()) == "")
}

@Test func nonLatinTextIsPreserved() {
    let v = values { $0.title = "夜のフェリー 🎧"; $0.artist = "مرحبا" }
    #expect(TextTemplate("{display}").render(v) == "مرحبا - 夜のフェリー 🎧")
}

@Test func unknownTokensAreReportedAndRenderedVerbatim() {
    let t = TextTemplate("{titel} {title} {time:huge}")
    #expect(t.unknownTokens == ["titel", "time:huge"])
    #expect(t.render(values()) == "{titel} Low Tide Radio {time:huge}")
}

@Test func literalBracesAndStaticText() {
    #expect(TextTemplate("{{title}").render(values()) == "{title}")
    #expect(TextTemplate("MACAMP").render(values()) == "MACAMP")
    #expect(TextTemplate("MACAMP").isDynamic == false)
    #expect(TextTemplate("{title}").isDynamic == true)
    #expect(TextTemplate("open { brace").render(values()) == "open { brace")
    #expect(TextTemplate("").render(values()) == "")
}

@Test func textMadeOnlyOfEmptyValuesAndPunctuationRendersAsNothing() {
    let nothing = TemplateValues()
    #expect(TextTemplate("{index}. {display}").render(nothing) == "")
    #expect(TextTemplate("{codec} · {sampleRate} · {bitrate} · {channels}").render(nothing) == "")
    #expect(TextTemplate("{index}. {display} ({duration})").render(nothing) == "")
    #expect(TextTemplate("{time:pad}").render(nothing) == "00:00")          // time always has a value
    #expect(TextTemplate("{index}/{count}").render(nothing) == "/0")          // count has a value, so the text stays
    #expect(TextTemplate("MACAMP").render(nothing) == "MACAMP")               // no tokens: literal text is untouched
    var some = TemplateValues()
    some.codec = "MP3"
    #expect(TextTemplate("{codec} · {sampleRate}").render(some) == "MP3 · ")
}
