sub init()
    m.top.functionName = "parseCaption"

    m.top.observeField("url", "fetchCaption")
    m.top.currentCaption = []
    m.nextCaption = invalid
    m.top.currentPos = 0

    m.captionTimer = m.top.findNode("captionTimer")
    m.captionTimer.ObserveField("fire", "updateCaption")

    m.captionList = CreateObject("roSGNode", "ContentNode")
    m.captionList.addFields({
        list: [],
        size: -1,
        tags: CreateObject("roRegex", "{\\an\d*}|&lt;.*?&gt;|<.*?>", "s")
    })
    m.reader = createObject("roUrlTransfer")
    m.font = CreateObject("roSGNode", "Font")

    ' Caption Style
    m.fontSizeDict = { "Default": 60, "Large": 60, "Extra Large": 70, "Medium": 50, "Small": 40 }
    m.percentageDict = { "Default": 1.0, "100%": 1.0, "75%": 0.75, "50%": 0.5, "25%": 0.25, "Off": 0 }
    m.textColorDict = { "Default": &HFFFFFFFF, "White": &HFFFFFFFF, "Black": &H000000FF, "Red": &HFF0000FF, "Green": &H008000FF, "Blue": &H0000FFFF, "Yellow": &HFFFF00FF, "Magenta": &HFF00FFFF, "Cyan": &H00FFFFFF }
    m.bgColorDict = { "Default": &H000000FF, "White": &HFFFFFFFF, "Black": &H000000FF, "Red": &HFF0000FF, "Green": &H008000FF, "Blue": &H0000FFFF, "Yellow": &HFFFF00FF, "Magenta": &HFF00FFFF, "Cyan": &H00FFFFFF }

    m.settings = CreateObject("roDeviceInfo")
    m.fontSize = m.fontSizeDict[m.settings.GetCaptionsOption("Text/Size")]
    m.textColor = m.textColorDict[m.settings.GetCaptionsOption("Text/Color")]
    m.textOpac = m.percentageDict[m.settings.GetCaptionsOption("Text/Opacity")]
    m.bgColor = m.bgColorDict[m.settings.GetCaptionsOption("Background/Color")]
    m.bgOpac = m.percentageDict[m.settings.GetCaptionsOption("Background/Opacity")]
    setFont()
end sub

sub setFont()
    fs = CreateObject("roFileSystem")
    fontlist = fs.Find("tmp:/", "font")
    if fontlist.count() > 0
        m.font.uri = "tmp:/" + fontlist[0]
        m.font.size = m.fontSize
    else
        reg = CreateObject("roFontRegistry")
        m.font = reg.GetDefaultFont(m.fontSize, false, false)
    end if
end sub

sub parseCaption()
    list = []
    if m.subtype = "vtt"
        list = parseVTT(m.text)
    else if m.subtype = "ass"
        list = parseASS(m.text)
    end if
    list.sortBy("start")
    m.captionList.list = list
end sub

sub fetchCaption()
    m.captionTimer.control = "stop"
    re = CreateObject("roRegex", "(http.*?\.(vtt|ass))", "s")
    url = re.match(m.top.url)
    if url[0] <> invalid
        m.reader.setUrl(url[0])
        m.text = m.reader.GetToString()
        m.subtype = url[2]

        m.top.control = "RUN"

        ' Clear the position
        m.captionTimer.control = "start"
    else
        m.captionTimer.control = "stop"
    end if
end sub

function newlabel(txt)
    label = CreateObject("roSGNode", "Label")
    label.text = txt
    label.font = m.font
    label.color = m.textColor
    label.opacity = m.textOpac
    return label
end function

function newLayoutGroup(labels)
    newlg = CreateObject("roSGNode", "LayoutGroup")
    newlg.appendchildren(labels)
    newlg.horizalignment = "center"
    newlg.vertalignment = "bottom"
    return newlg
end function

function newRect(lg)
    rectLG = CreateObject("roSGNode", "LayoutGroup")
    rectxy = lg.BoundingRect()
    rect = CreateObject("roSGNode", "Rectangle")
    rect.color = m.bgColor
    rect.opacity = m.bgOpac
    rect.width = rectxy.width + 50
    rect.height = rectxy.height
    if lg.getchildCount() = 0
        rect.width = 0
        rect.height = 0
    end if
    rectLG.translation = [0, -rect.height / 2]
    rectLG.horizalignment = "center"
    rectLG.vertalignment = "center"
    rectLG.appendchild(rect)
    return rectLG
end function

function captionFor(curPos)
    texts = []
    for each entry in m.captionList.list
        if entry["start"] <= curPos
            if curPos <= entry["end"]
                t = entry["text"]
                texts.push(t)
            end if
        else
            exit for
        end if
    end for
    return texts
end function

sub updateCaption ()
    m.top.currentCaption = []
    if LCase(m.top.playerState) = "playingon"
        m.top.currentPos = m.top.currentPos + 100
        if m.nextCaption = invalid
            m.nextCaption = captionFor(m.top.currentPos)
        end if

        labels = []
        for each text in m.nextCaption
            labels.push(newlabel (text))
        end for
        lines = newLayoutGroup(labels)
        rect = newRect(lines)
        m.top.currentCaption = [rect, lines]

        m.nextCaption = captionFor(m.top.currentPos + 100)
    else if LCase(m.top.playerState.right(1)) = "w"
        m.top.playerState = m.top.playerState.left(len (m.top.playerState) - 1)
    end if
end sub

function isTime(text)
    return text.right(1) = chr(31)
end function

function toMs(t)
    t = t.replace(".", ":")
    t = t.left(12)
    timestamp = t.tokenize(":")
    return 3600000 * timestamp[0].toint() + 60000 * timestamp[1].toint() + 1000 * timestamp[2].toint() + timestamp[3].toint()
end function

function parseVTT(lines)
    lines = lines.replace(" --> ", chr(31) + chr(10))
    lines = lines.split(chr(10))
    curStart = -1
    curEnd = -1
    entries = []

    for i = 0 to lines.count() - 1
        if isTime(lines[i])
            curStart = toMs (lines[i])
            curEnd = toMs (lines[i + 1])
            i += 1
        else if curStart <> -1
            trimmed = lines[i].trim()
            if trimmed <> chr(0)
                entry = { "start": curStart, "end": curEnd, "text": trimmed }
                entries.push(entry)
            end if
        end if
    end for
    return entries
end function

function trimASSText(text)
    text = text.trim()
    ' filter out style override
    ' TODO: honor the style and style override
    ' TODO: inline comments
    ' TODO: drawing command
    text = m.assControlSequence.ReplaceAll(text, "")
    text = text.split("\N")
    return text
end function

function parseASS(lines)
    m.assControlSequence = CreateObject("roRegex", "\{(?:[^}{]+|(?R))*+\}", "s")
    lines = lines.split(chr(10))

    startIndex = -1
    endIndex = -1
    textIndex = -1

    entries = []
    historyText = invalid
    historyStart = 0
    historyEnd = 0

    for i = 0 to lines.count() - 1
        line = lines[i].trim()
        if startIndex <> -1
            ' Dialogue:
            if line.left(9) = "Dialogue:"
                dialoge = line.mid(9).split(",")
                msStart = toMs(dialoge[startIndex].trim())
                msEnd = toMs(dialoge[endIndex].trim())
                if msStart >= msEnd
                    continue for
                end if

                text = []
                for j = textIndex to dialoge.count() - 1
                    text.push(dialoge[j])
                end for
                trimmed = trimASSText(text.join(","))

                for each t in trimmed
                    t = t.trim()
                    if t <> ""
                        ' filter based on this history
                        if historyText = t and msStart <= historyEnd
                            ' TODO: if?
                            historyEnd = msEnd
                        else 'emit
                            if historyText <> invalid
                                entry = { "start": historyStart, "end": historyEnd, "text": historyText }
                                entries.push(entry)
                            end if
                            historyText = t
                            historyStart = msStart
                            historyEnd = msEnd
                        end if
                    end if
                end for
            end if
        else if line.left(7) = "Format:"
            ' Format
            format = line.mid(7).tokenize(",")
            for j = 0 to format.count() - 1
                f = format[j].trim()
                if f = "Start"
                    startIndex = j
                else if f = "End"
                    endIndex = j
                else if f = "Text"
                    ' Text should always be the last field
                    textIndex = j
                end if
            end for
        end if
    end for

    'emit last
    if historyText <> invalid
        entry = { "start": historyStart, "end": historyEnd, "text": historyText }
        entries.push(entry)
    end if

    return entries
end function
