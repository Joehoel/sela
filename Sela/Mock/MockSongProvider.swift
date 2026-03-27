import Foundation

struct MockSongProvider: SongProvider {
    func loadSongs() async -> [Song] {
        [
            Self.wayMaker,
            Self.buildMyLife,
            Self.greatAreYouLord,
            Self.tenThousandReasons,
            Self.amazingGrace,
            Self.blessedBeYourName,
        ]
    }
}

// MARK: - Songs extracted from real ProPresenter library

extension MockSongProvider {

    static var wayMaker: Song {
        Song(
            id: "DE6B4FD6-DF41-4F1A-8AC7-6D8552A14C13",
            title: "Way Maker",
            category: "Modern Worship",
            slideGroups: [
                SlideGroup(name: "Verse 1", slides: [
                    Slide(lines: [SlideLine(original: "You are here, moving in our midst")]),
                    Slide(lines: [SlideLine(original: "I worship You, I worship You")]),
                    Slide(lines: [SlideLine(original: "You are here, working in this place")]),
                    Slide(lines: [SlideLine(original: "I worship You, I worship You")]),
                ]),
                SlideGroup(name: "Chorus", slides: [
                    Slide(lines: [SlideLine(original: "Way maker, miracle worker")]),
                    Slide(lines: [SlideLine(original: "Promise keeper, light in the darkness")]),
                    Slide(lines: [SlideLine(original: "My God, that is who You are")]),
                ]),
                SlideGroup(name: "Verse 2", slides: [
                    Slide(lines: [SlideLine(original: "You are here, touching every heart")]),
                    Slide(lines: [SlideLine(original: "I worship You, I worship You")]),
                    Slide(lines: [SlideLine(original: "You are here, healing every heart")]),
                    Slide(lines: [SlideLine(original: "I worship You, I worship You")]),
                ]),
                SlideGroup(name: "Verse 3", slides: [
                    Slide(lines: [SlideLine(original: "You are here, turning lives around")]),
                    Slide(lines: [SlideLine(original: "I worship You, I worship You")]),
                    Slide(lines: [SlideLine(original: "You are here, mending every heart")]),
                    Slide(lines: [SlideLine(original: "I worship You, I worship You")]),
                ]),
                SlideGroup(name: "Bridge 1", slides: [
                    Slide(lines: [SlideLine(original: "Even when I don't see it, You're working")]),
                    Slide(lines: [SlideLine(original: "Even when I don't feel it, You're working")]),
                    Slide(lines: [SlideLine(original: "You never stop, You never stop working")]),
                ]),
            ]
        )
    }

    static var buildMyLife: Song {
        Song(
            id: "F10C37C5-0144-4E87-9A62-C168E86BEEF7",
            title: "Build My Life",
            category: "Modern Worship",
            slideGroups: [
                SlideGroup(name: "Verse 1", slides: [
                    Slide(lines: [SlideLine(original: "Worthy of every song we could ever sing", translation: "Elk lied dat we ooit zouden kunnen zingen waardig")]),
                    Slide(lines: [SlideLine(original: "Worthy of all the praise we could ever bring", translation: "Alle lof waard die we ooit zouden kunnen geven")]),
                    Slide(lines: [SlideLine(original: "Worthy of every breath we could ever breathe", translation: "Elke ademtocht die we ooit zouden kunnen nemen waard")]),
                    Slide(lines: [SlideLine(original: "We live for You", translation: "Wij leven voor U")]),
                ]),
                SlideGroup(name: "Verse 2", slides: [
                    Slide(lines: [SlideLine(original: "Jesus, the name above every other name", translation: "Jezus, de naam boven alle andere namen")]),
                    Slide(lines: [SlideLine(original: "Jesus, the only One who could ever save", translation: "Jezus, de enige die ooit kon redden")]),
                    Slide(lines: [SlideLine(original: "Worthy of every breath we could ever breathe", translation: "Elke ademtocht die we ooit zouden kunnen nemen waard")]),
                    Slide(lines: [SlideLine(original: "We live for You, we live for You", translation: "Wij leven voor U, wij leven voor U")]),
                ]),
                SlideGroup(name: "Chorus", slides: [
                    Slide(lines: [SlideLine(original: "Holy, there is no one like You", translation: "Heilig, er is niemand zoals U")]),
                    Slide(lines: [SlideLine(original: "There is none beside You", translation: "Er is niemand naast U")]),
                    Slide(lines: [SlideLine(original: "Open up my eyes in wonder", translation: "Open mijn ogen in verwondering")]),
                    Slide(lines: [SlideLine(original: "And show me who You are", translation: "En laat me zien wie U bent")]),
                    Slide(lines: [SlideLine(original: "And fill me with Your heart", translation: "En vul mij met Uw hart")]),
                    Slide(lines: [SlideLine(original: "And lead me in Your love to those around me", translation: "En leid mij in Uw liefde naar de mensen om mij heen")]),
                ]),
                SlideGroup(name: "Bridge 1", slides: [
                    Slide(lines: [SlideLine(original: "I will build my life upon Your love", translation: "Ik zal mijn leven bouwen op Uw liefde")]),
                    Slide(lines: [SlideLine(original: "It is a firm foundation", translation: "Het is een stevig fundament")]),
                    Slide(lines: [SlideLine(original: "I will put my trust in You alone", translation: "Ik zal alleen op U vertrouwen")]),
                    Slide(lines: [SlideLine(original: "And I will not be shaken", translation: "En ik zal niet wankelen")]),
                ]),
            ]
        )
    }

    static var greatAreYouLord: Song {
        Song(
            id: "47898003-1A89-4397-B73A-85394983FF1E",
            title: "Great Are You Lord",
            category: "Modern Worship",
            slideGroups: [
                SlideGroup(name: "Verse 1", slides: [
                    Slide(lines: [SlideLine(original: "You give life, You are love")]),
                    Slide(lines: [SlideLine(original: "You bring light to the darkness")]),
                    Slide(lines: [SlideLine(original: "You give hope, You restore")]),
                    Slide(lines: [SlideLine(original: "Every heart that is broken")]),
                ]),
                SlideGroup(name: "Chorus", slides: [
                    Slide(lines: [SlideLine(original: "Great are You Lord")]),
                    Slide(lines: [SlideLine(original: "It's Your breath in our lungs")]),
                    Slide(lines: [SlideLine(original: "So we pour out our praise")]),
                    Slide(lines: [SlideLine(original: "We pour out our praise")]),
                    Slide(lines: [SlideLine(original: "It's Your breath in our lungs")]),
                    Slide(lines: [SlideLine(original: "So we pour out our praise to You only")]),
                ]),
                SlideGroup(name: "Bridge 1", slides: [
                    Slide(lines: [SlideLine(original: "All the earth will shout Your praise")]),
                    Slide(lines: [SlideLine(original: "Our hearts will cry, these bones will sing")]),
                    Slide(lines: [SlideLine(original: "Great are You Lord")]),
                ]),
            ]
        )
    }

    static var tenThousandReasons: Song {
        Song(
            id: "22CDF97B-B435-4FF0-8746-30BD07F9CD52",
            title: "10,000 Reasons (Bless the Lord)",
            category: "Contemporary",
            slideGroups: [
                SlideGroup(name: "Chorus", slides: [
                    Slide(lines: [SlideLine(original: "Bless the Lord, O my soul", translation: "Loof de Heer, mijn ziel")]),
                    Slide(lines: [SlideLine(original: "O my soul, worship His holy name", translation: "O mijn ziel, aanbid Zijn heilige naam")]),
                    Slide(lines: [SlideLine(original: "Sing like never before, O my soul", translation: "Zing als nooit tevoren, o mijn ziel")]),
                    Slide(lines: [SlideLine(original: "I'll worship Your holy name", translation: "Ik zal Uw heilige naam aanbidden")]),
                ]),
                SlideGroup(name: "Verse 1", slides: [
                    Slide(lines: [SlideLine(original: "The sun comes up, it's a new day dawning", translation: "De zon komt op, het is een nieuwe dag die aanbreekt")]),
                    Slide(lines: [SlideLine(original: "It's time to sing Your song again", translation: "Het is tijd om Uw lied weer te zingen")]),
                    Slide(lines: [SlideLine(original: "Whatever may pass and whatever lies before me", translation: "Wat er ook gebeurt en wat er ook voor mij ligt")]),
                    Slide(lines: [SlideLine(original: "Let me be singing when the evening comes", translation: "Laat me zingen als de avond valt")]),
                ]),
                SlideGroup(name: "Verse 2", slides: [
                    Slide(lines: [SlideLine(original: "You're rich in love and You're slow to anger", translation: "U bent rijk aan liefde en langzaam tot toorn")]),
                    Slide(lines: [SlideLine(original: "Your name is great and Your heart is kind", translation: "Uw naam is groot en Uw hart is goed")]),
                    Slide(lines: [SlideLine(original: "For all Your goodness I will keep on singing", translation: "Voor al Uw goedheid zal ik blijven zingen")]),
                    Slide(lines: [SlideLine(original: "Ten thousand reasons for my heart to find", translation: "Tienduizend redenen voor mijn hart om te vinden")]),
                ]),
                SlideGroup(name: "Verse 3", slides: [
                    Slide(lines: [SlideLine(original: "And on that day when my strength is failing", translation: "En op die dag waarop mijn krachten mij verlaten")]),
                    Slide(lines: [SlideLine(original: "The end draws near and my time has come", translation: "Het einde nadert en mijn tijd is gekomen")]),
                    Slide(lines: [SlideLine(original: "Still my soul will sing Your praise unending", translation: "Toch zal mijn ziel Uw lof bezingen, zonder einde")]),
                    Slide(lines: [SlideLine(original: "Ten thousand years and then forevermore", translation: "Tienduizend jaar en daarna voor altijd")]),
                ]),
            ]
        )
    }

    static var amazingGrace: Song {
        Song(
            id: "87566B14-432C-46EB-B988-D10BC4E978BE",
            title: "Amazing Grace",
            category: "Hymns",
            slideGroups: [
                SlideGroup(name: "Verse 1", slides: [
                    Slide(lines: [SlideLine(original: "Amazing grace, how sweet the sound", translation: "Genade, zo oneindig groot")]),
                    Slide(lines: [SlideLine(original: "That saved a wretch like me", translation: "Dat ik, die 't niet verdien")]),
                    Slide(lines: [SlideLine(original: "I once was lost, but now am found", translation: "Het leven vond, want ik was dood")]),
                    Slide(lines: [SlideLine(original: "Was blind, but now I see", translation: "En blind, maar nu kan ik zien")]),
                ]),
                SlideGroup(name: "Verse 2", slides: [
                    Slide(lines: [SlideLine(original: "'Twas grace that taught my heart to fear")]),
                    Slide(lines: [SlideLine(original: "And grace my fears relieved")]),
                    Slide(lines: [SlideLine(original: "How precious did that grace appear")]),
                    Slide(lines: [SlideLine(original: "The hour I first believed")]),
                ]),
                SlideGroup(name: "Verse 3", slides: [
                    Slide(lines: [SlideLine(original: "Through many dangers, toils, and snares")]),
                    Slide(lines: [SlideLine(original: "I have already come")]),
                    Slide(lines: [SlideLine(original: "'Tis grace hath brought me safe thus far")]),
                    Slide(lines: [SlideLine(original: "And grace will lead me home")]),
                ]),
                SlideGroup(name: "Verse 4", slides: [
                    Slide(lines: [SlideLine(original: "When we've been there ten thousand years")]),
                    Slide(lines: [SlideLine(original: "Bright shining as the sun")]),
                    Slide(lines: [SlideLine(original: "We've no less days to sing God's praise")]),
                    Slide(lines: [SlideLine(original: "Than when we first begun")]),
                ]),
            ]
        )
    }

    static var blessedBeYourName: Song {
        Song(
            id: "6F82F53D-143A-4D9A-ABE8-D9E537B08479",
            title: "Blessed Be Your Name",
            category: "Modern Worship",
            slideGroups: [
                SlideGroup(name: "Verse 1", slides: [
                    Slide(lines: [SlideLine(original: "Blessed be Your name")]),
                    Slide(lines: [SlideLine(original: "In the land that is plentiful")]),
                    Slide(lines: [SlideLine(original: "Where Your streams of abundance flow")]),
                    Slide(lines: [SlideLine(original: "Blessed be Your name")]),
                ]),
                SlideGroup(name: "Verse 2", slides: [
                    Slide(lines: [SlideLine(original: "Blessed be Your name")]),
                    Slide(lines: [SlideLine(original: "When I'm found in the desert place")]),
                    Slide(lines: [SlideLine(original: "Though I walk through the wilderness")]),
                    Slide(lines: [SlideLine(original: "Blessed be Your name")]),
                ]),
                SlideGroup(name: "Chorus", slides: [
                    Slide(lines: [SlideLine(original: "Every blessing You pour out I'll turn back to praise")]),
                    Slide(lines: [SlideLine(original: "When the darkness closes in, Lord, still I will say")]),
                    Slide(lines: [SlideLine(original: "Blessed be the name of the Lord")]),
                    Slide(lines: [SlideLine(original: "Blessed be Your name")]),
                    Slide(lines: [SlideLine(original: "Blessed be the name of the Lord")]),
                    Slide(lines: [SlideLine(original: "Blessed be Your glorious name")]),
                ]),
                SlideGroup(name: "Bridge 1", slides: [
                    Slide(lines: [SlideLine(original: "You give and take away")]),
                    Slide(lines: [SlideLine(original: "You give and take away")]),
                    Slide(lines: [SlideLine(original: "My heart will choose to say")]),
                    Slide(lines: [SlideLine(original: "Lord, blessed be Your name")]),
                ]),
            ]
        )
    }
}
