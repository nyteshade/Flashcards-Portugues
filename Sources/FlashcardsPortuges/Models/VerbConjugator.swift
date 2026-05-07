import Foundation

struct ConjugationForm: Identifiable {
    let id = UUID()
    let pronoun: String
    let form: String
}

struct TenseGroup: Identifiable {
    let id = UUID()
    let name: String
    let forms: [ConjugationForm]
}

struct VerbConjugation {
    let infinitive: String
    let english: String
    let tenses: [TenseGroup]
}

enum VerbType {
    case ar, er, ir, irregular

    static func of(_ verb: String) -> VerbType {
        let v = verb.lowercased()
        if VerbConjugator.irregularVerbs.keys.contains(v) { return .irregular }
        if v.hasSuffix("ar") { return .ar }
        if v.hasSuffix("er") { return .er }
        if v.hasSuffix("ir") { return .ir }
        return .ar
    }
}

func conjugate(_ verb: String) -> VerbConjugation? {
    let v = verb.lowercased().trimmingCharacters(in: .whitespaces)
    guard v.hasSuffix("ar") || v.hasSuffix("er") || v.hasSuffix("ir") else { return nil }
    return VerbConjugator.conjugate(v, english: verb)
}

struct VerbConjugator {

    static let pronouns = ["eu", "tu", "você/ele/ela", "nós", "vós", "vocês/eles/elas"]

    static let tenseOrder: [String] = [
        "Presente do Indicativo",
        "Pretérito Perfeito",
        "Pretérito Imperfeito",
        "Pretérito Mais-que-Perfeito",
        "Futuro do Presente",
        "Futuro do Pretérito",
        "Presente do Subjuntivo",
        "Pretérito Imperfeito do Subjuntivo",
        "Futuro do Subjuntivo",
        "Imperativo Afirmativo",
    ]

    static let irregularVerbs: [String: [String: [String]]] = [

        // ── core auxiliaries & high-frequency ──
        "ser": [
            "Presente do Indicativo":  ["sou", "és", "é", "somos", "sois", "são"],
            "Pretérito Perfeito":      ["fui", "foste", "foi", "fomos", "fostes", "foram"],
            "Pretérito Imperfeito":    ["era", "eras", "era", "éramos", "éreis", "eram"],
            "Futuro do Presente":      ["serei", "serás", "será", "seremos", "sereis", "serão"],
            "Futuro do Pretérito":     ["seria", "serias", "seria", "seríamos", "seríeis", "seriam"],
            "Presente do Subjuntivo":  ["seja", "sejas", "seja", "sejamos", "sejais", "sejam"],
            "Pretérito Imperfeito do Subjuntivo": ["fosse", "fosses", "fosse", "fôssemos", "fôsseis", "fossem"],
            "Futuro do Subjuntivo":    ["for", "fores", "for", "formos", "fordes", "forem"],
            "Imperativo Afirmativo":   ["—", "sê", "seja", "sejamos", "sede", "sejam"],
        ],
        "estar": [
            "Presente do Indicativo":  ["estou", "estás", "está", "estamos", "estais", "estão"],
            "Pretérito Perfeito":      ["estive", "estiveste", "esteve", "estivemos", "estivestes", "estiveram"],
            "Pretérito Imperfeito":    ["estava", "estavas", "estava", "estávamos", "estáveis", "estavam"],
            "Futuro do Presente":      ["estarei", "estarás", "estará", "estaremos", "estareis", "estarão"],
            "Futuro do Pretérito":     ["estaria", "estarias", "estaria", "estaríamos", "estaríeis", "estariam"],
            "Presente do Subjuntivo":  ["esteja", "estejas", "esteja", "estejamos", "estejais", "estejam"],
            "Pretérito Imperfeito do Subjuntivo": ["estivesse", "estivesses", "estivesse", "estivéssemos", "estivésseis", "estivessem"],
            "Futuro do Subjuntivo":    ["estiver", "estiveres", "estiver", "estivermos", "estiverdes", "estiverem"],
            "Imperativo Afirmativo":   ["—", "está", "esteja", "estejamos", "estai", "estejam"],
        ],
        "ter": [
            "Presente do Indicativo":  ["tenho", "tens", "tem", "temos", "tendes", "têm"],
            "Pretérito Perfeito":      ["tive", "tiveste", "teve", "tivemos", "tivestes", "tiveram"],
            "Pretérito Imperfeito":    ["tinha", "tinhas", "tinha", "tínhamos", "tínheis", "tinham"],
            "Futuro do Presente":      ["terei", "terás", "terá", "teremos", "tereis", "terão"],
            "Futuro do Pretérito":     ["teria", "terias", "teria", "teríamos", "teríeis", "teriam"],
            "Presente do Subjuntivo":  ["tenha", "tenhas", "tenha", "tenhamos", "tenhais", "tenham"],
            "Pretérito Imperfeito do Subjuntivo": ["tivesse", "tivesses", "tivesse", "tivéssemos", "tivésseis", "tivessem"],
            "Futuro do Subjuntivo":    ["tiver", "tiveres", "tiver", "tivermos", "tiverdes", "tiverem"],
            "Imperativo Afirmativo":   ["—", "tem", "tenha", "tenhamos", "tende", "tenham"],
        ],
        "ir": [
            "Presente do Indicativo":  ["vou", "vais", "vai", "vamos", "ides", "vão"],
            "Pretérito Perfeito":      ["fui", "foste", "foi", "fomos", "fostes", "foram"],
            "Pretérito Imperfeito":    ["ia", "ias", "ia", "íamos", "íeis", "iam"],
            "Futuro do Presente":      ["irei", "irás", "irá", "iremos", "ireis", "irão"],
            "Futuro do Pretérito":     ["iria", "irias", "iria", "iríamos", "iríeis", "iriam"],
            "Presente do Subjuntivo":  ["vá", "vás", "vá", "vamos", "vades", "vão"],
            "Pretérito Imperfeito do Subjuntivo": ["fosse", "fosses", "fosse", "fôssemos", "fôsseis", "fossem"],
            "Futuro do Subjuntivo":    ["for", "fores", "for", "formos", "fordes", "forem"],
            "Imperativo Afirmativo":   ["—", "vai", "vá", "vamos", "ide", "vão"],
        ],
        "fazer": [
            "Presente do Indicativo":  ["faço", "fazes", "faz", "fazemos", "fazeis", "fazem"],
            "Pretérito Perfeito":      ["fiz", "fizeste", "fez", "fizemos", "fizestes", "fizeram"],
            "Pretérito Imperfeito":    ["fazia", "fazias", "fazia", "fazíamos", "fazíeis", "faziam"],
            "Futuro do Presente":      ["farei", "farás", "fará", "faremos", "fareis", "farão"],
            "Futuro do Pretérito":     ["faria", "farias", "faria", "faríamos", "faríeis", "fariam"],
            "Presente do Subjuntivo":  ["faça", "faças", "faça", "façamos", "façais", "façam"],
            "Pretérito Imperfeito do Subjuntivo": ["fizesse", "fizesses", "fizesse", "fizéssemos", "fizésseis", "fizessem"],
            "Futuro do Subjuntivo":    ["fizer", "fizeres", "fizer", "fizermos", "fizerdes", "fizerem"],
            "Imperativo Afirmativo":   ["—", "faz", "faça", "façamos", "fazei", "façam"],
        ],
        "dizer": [
            "Presente do Indicativo":  ["digo", "dizes", "diz", "dizemos", "dizeis", "dizem"],
            "Pretérito Perfeito":      ["disse", "disseste", "disse", "dissemos", "dissestes", "disseram"],
            "Pretérito Imperfeito":    ["dizia", "dizias", "dizia", "dizíamos", "dizíeis", "diziam"],
            "Futuro do Presente":      ["direi", "dirás", "dirá", "diremos", "direis", "dirão"],
            "Futuro do Pretérito":     ["diria", "dirias", "diria", "diríamos", "diríeis", "diriam"],
            "Presente do Subjuntivo":  ["diga", "digas", "diga", "digamos", "digais", "digam"],
            "Pretérito Imperfeito do Subjuntivo": ["dissesse", "dissesses", "dissesse", "disséssemos", "dissésseis", "dissessem"],
            "Futuro do Subjuntivo":    ["disser", "disseres", "disser", "dissermos", "disserdes", "disserem"],
            "Imperativo Afirmativo":   ["—", "diz", "diga", "digamos", "dizei", "digam"],
        ],
        "poder": [
            "Presente do Indicativo":  ["posso", "podes", "pode", "podemos", "podeis", "podem"],
            "Pretérito Perfeito":      ["pude", "pudeste", "pôde", "pudemos", "pudestes", "puderam"],
            "Pretérito Imperfeito":    ["podia", "podias", "podia", "podíamos", "podíeis", "podiam"],
            "Futuro do Presente":      ["poderei", "poderás", "poderá", "poderemos", "podereis", "poderão"],
            "Futuro do Pretérito":     ["poderia", "poderias", "poderia", "poderíamos", "poderíeis", "poderiam"],
            "Presente do Subjuntivo":  ["possa", "possas", "possa", "possamos", "possais", "possam"],
            "Pretérito Imperfeito do Subjuntivo": ["pudesse", "pudesses", "pudesse", "pudéssemos", "pudésseis", "pudessem"],
            "Futuro do Subjuntivo":    ["puder", "puderes", "puder", "pudermos", "puderdes", "puderem"],
            "Imperativo Afirmativo":   ["—", "pode", "possa", "possamos", "podei", "possam"],
        ],
        "saber": [
            "Presente do Indicativo":  ["sei", "sabes", "sabe", "sabemos", "sabeis", "sabem"],
            "Pretérito Perfeito":      ["soube", "soubeste", "soube", "soubemos", "soubestes", "souberam"],
            "Pretérito Imperfeito":    ["sabia", "sabias", "sabia", "sabíamos", "sabíeis", "sabiam"],
            "Futuro do Presente":      ["saberei", "saberás", "saberá", "saberemos", "sabereis", "saberão"],
            "Futuro do Pretérito":     ["saberia", "saberias", "saberia", "saberíamos", "saberíeis", "saberiam"],
            "Presente do Subjuntivo":  ["saiba", "saibas", "saiba", "saibamos", "saibais", "saibam"],
            "Pretérito Imperfeito do Subjuntivo": ["soubesse", "soubesses", "soubesse", "soubéssemos", "soubésseis", "soubessem"],
            "Futuro do Subjuntivo":    ["souber", "souberes", "souber", "soubermos", "souberdes", "souberem"],
            "Imperativo Afirmativo":   ["—", "sabe", "saiba", "saibamos", "sabei", "saibam"],
        ],
        "ver": [
            "Presente do Indicativo":  ["vejo", "vês", "vê", "vemos", "vedes", "veem"],
            "Pretérito Perfeito":      ["vi", "viste", "viu", "vimos", "vistes", "viram"],
            "Pretérito Imperfeito":    ["via", "vias", "via", "víamos", "víeis", "viam"],
            "Futuro do Presente":      ["verei", "verás", "verá", "veremos", "vereis", "verão"],
            "Futuro do Pretérito":     ["veria", "verias", "veria", "veríamos", "veríeis", "veriam"],
            "Presente do Subjuntivo":  ["veja", "vejas", "veja", "vejamos", "vejais", "vejam"],
            "Pretérito Imperfeito do Subjuntivo": ["visse", "visses", "visse", "víssemos", "vísseis", "vissem"],
            "Futuro do Subjuntivo":    ["vir", "vires", "vir", "virmos", "virdes", "virem"],
            "Imperativo Afirmativo":   ["—", "vê", "veja", "vejamos", "vede", "vejam"],
        ],
        "vir": [
            "Presente do Indicativo":  ["venho", "vens", "vem", "vimos", "vindes", "vêm"],
            "Pretérito Perfeito":      ["vim", "vieste", "veio", "viemos", "viestes", "vieram"],
            "Pretérito Imperfeito":    ["vinha", "vinhas", "vinha", "vínhamos", "vínheis", "vinham"],
            "Futuro do Presente":      ["virei", "virás", "virá", "viremos", "vireis", "virão"],
            "Futuro do Pretérito":     ["viria", "virias", "viria", "viríamos", "viríeis", "viriam"],
            "Presente do Subjuntivo":  ["venha", "venhas", "venha", "venhamos", "venhais", "venham"],
            "Pretérito Imperfeito do Subjuntivo": ["viesse", "viesses", "viesse", "viéssemos", "viésseis", "viessem"],
            "Futuro do Subjuntivo":    ["vier", "vieres", "vier", "viermos", "vierdes", "vierem"],
            "Imperativo Afirmativo":   ["—", "vem", "venha", "venhamos", "vinde", "venham"],
        ],
        "querer": [
            "Presente do Indicativo":  ["quero", "queres", "quer", "queremos", "quereis", "querem"],
            "Pretérito Perfeito":      ["quis", "quiseste", "quis", "quisemos", "quisestes", "quiseram"],
            "Pretérito Imperfeito":    ["queria", "querias", "queria", "queríamos", "queríeis", "queriam"],
            "Futuro do Presente":      ["quererei", "quererás", "quererá", "quereremos", "querereis", "quererão"],
            "Futuro do Pretérito":     ["quereria", "quererias", "quereria", "quereríamos", "quereríeis", "quereriam"],
            "Presente do Subjuntivo":  ["queira", "queiras", "queira", "queiramos", "queirais", "queiram"],
            "Pretérito Imperfeito do Subjuntivo": ["quisesse", "quisesses", "quisesse", "quiséssemos", "quisésseis", "quisessem"],
            "Futuro do Subjuntivo":    ["quiser", "quiseres", "quiser", "quisermos", "quiserdes", "quiserem"],
            "Imperativo Afirmativo":   ["—", "quer", "queira", "queiramos", "querei", "queiram"],
        ],
        "haver": [
            "Presente do Indicativo":  ["hei", "hás", "há", "havemos", "haveis", "hão"],
            "Pretérito Perfeito":      ["houve", "houveste", "houve", "houvemos", "houvestes", "houveram"],
            "Pretérito Imperfeito":    ["havia", "havias", "havia", "havíamos", "havíeis", "haviam"],
            "Futuro do Presente":      ["haverei", "haverás", "haverá", "haveremos", "havereis", "haverão"],
            "Futuro do Pretérito":     ["haveria", "haverias", "haveria", "haveríamos", "haveríeis", "haveriam"],
            "Presente do Subjuntivo":  ["haja", "hajas", "haja", "hajamos", "hajais", "hajam"],
            "Pretérito Imperfeito do Subjuntivo": ["houvesse", "houvesses", "houvesse", "houvéssemos", "houvésseis", "houvessem"],
            "Futuro do Subjuntivo":    ["houver", "houveres", "houver", "houvermos", "houverdes", "houverem"],
            "Imperativo Afirmativo":   ["—", "há", "haja", "hajamos", "havei", "hajam"],
        ],
        "dar": [
            "Presente do Indicativo":  ["dou", "dás", "dá", "damos", "dais", "dão"],
            "Pretérito Perfeito":      ["dei", "deste", "deu", "demos", "destes", "deram"],
            "Pretérito Imperfeito":    ["dava", "davas", "dava", "dávamos", "dáveis", "davam"],
            "Futuro do Presente":      ["darei", "darás", "dará", "daremos", "dareis", "darão"],
            "Futuro do Pretérito":     ["daria", "darias", "daria", "daríamos", "daríeis", "dariam"],
            "Presente do Subjuntivo":  ["dê", "dês", "dê", "demos", "deis", "deem"],
            "Pretérito Imperfeito do Subjuntivo": ["desse", "desses", "desse", "déssemos", "désseis", "dessem"],
            "Futuro do Subjuntivo":    ["der", "deres", "der", "dermos", "derdes", "derem"],
            "Imperativo Afirmativo":   ["—", "dá", "dê", "demos", "dai", "deem"],
        ],

        // ── pôr & compounds (follow same pattern) ──
        "pôr": [
            "Presente do Indicativo":  ["ponho", "pões", "põe", "pomos", "pondes", "põem"],
            "Pretérito Perfeito":      ["pus", "puseste", "pôs", "pusemos", "pusestes", "puseram"],
            "Pretérito Imperfeito":    ["punha", "punhas", "punha", "púnhamos", "púnheis", "punham"],
            "Futuro do Presente":      ["porei", "porás", "porá", "poremos", "poreis", "porão"],
            "Futuro do Pretérito":     ["poria", "porias", "poria", "poríamos", "poríeis", "poriam"],
            "Presente do Subjuntivo":  ["ponha", "ponhas", "ponha", "ponhamos", "ponhais", "ponham"],
            "Pretérito Imperfeito do Subjuntivo": ["pusesse", "pusesses", "pusesse", "puséssemos", "pusésseis", "pusessem"],
            "Futuro do Subjuntivo":    ["puser", "puseres", "puser", "pusermos", "puserdes", "puserem"],
            "Imperativo Afirmativo":   ["—", "põe", "ponha", "ponhamos", "ponde", "ponham"],
        ],
        "compor": [
            "Presente do Indicativo":  ["componho", "compões", "compõe", "compomos", "compondes", "compõem"],
            "Pretérito Perfeito":      ["compus", "compuseste", "compôs", "compusemos", "compusestes", "compuseram"],
            "Pretérito Imperfeito":    ["compunha", "compunhas", "compunha", "compúnhamos", "compúnheis", "compunham"],
            "Futuro do Presente":      ["comporei", "comporás", "comporá", "comporemos", "comporeis", "comporão"],
            "Futuro do Pretérito":     ["comporia", "comporias", "comporia", "comporíamos", "comporíeis", "comporiam"],
            "Presente do Subjuntivo":  ["componha", "componhas", "componha", "componhamos", "componhais", "componham"],
            "Pretérito Imperfeito do Subjuntivo": ["compusesse", "compusesses", "compusesse", "compuséssemos", "compusésseis", "compusessem"],
            "Futuro do Subjuntivo":    ["compuser", "compuseres", "compuser", "compusermos", "compuserdes", "compuserem"],
            "Imperativo Afirmativo":   ["—", "compõe", "componha", "componhamos", "compôde", "componham"],
        ],
        "dispor": [
            "Presente do Indicativo":  ["disponho", "dispões", "dispõe", "dispomos", "dispondes", "dispõem"],
            "Pretérito Perfeito":      ["dispus", "dispuseste", "dispôs", "dispusemos", "dispusestes", "dispuseram"],
            "Pretérito Imperfeito":    ["dispunha", "dispunhas", "dispunha", "dispúnhamos", "dispúnheis", "dispunham"],
            "Futuro do Presente":      ["disporei", "disporás", "disporá", "disporemos", "disporeis", "disporão"],
            "Futuro do Pretérito":     ["disporia", "disporias", "disporia", "disporíamos", "disporíeis", "disporiam"],
            "Presente do Subjuntivo":  ["disponha", "disponhas", "disponha", "disponhamos", "disponhais", "disponham"],
            "Pretérito Imperfeito do Subjuntivo": ["dispusesse", "dispusesses", "dispusesse", "dispuséssemos", "dispusésseis", "dispusessem"],
            "Futuro do Subjuntivo":    ["dispuser", "dispuseres", "dispuser", "dispusermos", "dispuserdes", "dispuserem"],
            "Imperativo Afirmativo":   ["—", "dispõe", "disponha", "disponhamos", "dispôde", "disponham"],
        ],
        "expor": [
            "Presente do Indicativo":  ["exponho", "expões", "expõe", "expomos", "expondes", "expõem"],
            "Pretérito Perfeito":      ["expus", "expuseste", "expôs", "expusemos", "expusestes", "expuseram"],
            "Pretérito Imperfeito":    ["expunha", "expunhas", "expunha", "expúnhamos", "expúnheis", "expunham"],
            "Futuro do Presente":      ["exporei", "exporás", "exporá", "exporemos", "exporeis", "exporão"],
            "Futuro do Pretérito":     ["exporia", "exporias", "exporia", "exporíamos", "exporíeis", "exporiam"],
            "Presente do Subjuntivo":  ["exponha", "exponhas", "exponha", "exponhamos", "exponhais", "exponham"],
            "Pretérito Imperfeito do Subjuntivo": ["expusesse", "expusesses", "expusesse", "expuséssemos", "expusésseis", "expusessem"],
            "Futuro do Subjuntivo":    ["expuser", "expuseres", "expuser", "expusermos", "expuserdes", "expuserem"],
            "Imperativo Afirmativo":   ["—", "expõe", "exponha", "exponhamos", "expôde", "exponham"],
        ],
        "impor": [
            "Presente do Indicativo":  ["imponho", "impões", "impõe", "impomos", "impondes", "impõem"],
            "Pretérito Perfeito":      ["impus", "impuseste", "impôs", "impusemos", "impusestes", "impuseram"],
            "Pretérito Imperfeito":    ["impunha", "impunhas", "impunha", "impúnhamos", "impúnheis", "impunham"],
            "Futuro do Presente":      ["imporei", "imporás", "imporá", "imporemos", "imporeis", "imporão"],
            "Futuro do Pretérito":     ["imporia", "imporias", "imporia", "imporíamos", "imporíeis", "imporiam"],
            "Presente do Subjuntivo":  ["imponha", "imponhas", "imponha", "imponhamos", "imponhais", "imponham"],
            "Pretérito Imperfeito do Subjuntivo": ["impusesse", "impusesses", "impusesse", "impuséssemos", "impusésseis", "impusessem"],
            "Futuro do Subjuntivo":    ["impuser", "impuseres", "impuser", "impusermos", "impuserdes", "impuserem"],
            "Imperativo Afirmativo":   ["—", "impõe", "imponha", "imponhamos", "impôde", "imponham"],
        ],
        "opor": [
            "Presente do Indicativo":  ["oponho", "opões", "opõe", "opomos", "opondes", "opõem"],
            "Pretérito Perfeito":      ["opus", "opuseste", "opôs", "opusemos", "opusestes", "opuseram"],
            "Pretérito Imperfeito":    ["opunha", "opunhas", "opunha", "opúnhamos", "opúnheis", "opunham"],
            "Futuro do Presente":      ["oporei", "oporás", "oporá", "oporemos", "oporeis", "oporão"],
            "Futuro do Pretérito":     ["oporia", "oporias", "oporia", "oporíamos", "oporíeis", "oporiam"],
            "Presente do Subjuntivo":  ["oponha", "oponhas", "oponha", "oponhamos", "oponhais", "oponham"],
            "Pretérito Imperfeito do Subjuntivo": ["opusesse", "opusesses", "opusesse", "opuséssemos", "opusésseis", "opusessem"],
            "Futuro do Subjuntivo":    ["opuser", "opuseres", "opuser", "opusermos", "opuserdes", "opuserem"],
            "Imperativo Afirmativo":   ["—", "opõe", "oponha", "oponhamos", "opôde", "oponham"],
        ],
        "propor": [
            "Presente do Indicativo":  ["proponho", "propões", "propõe", "propomos", "propondes", "propõem"],
            "Pretérito Perfeito":      ["propus", "propuseste", "propôs", "propusemos", "propusestes", "propuseram"],
            "Pretérito Imperfeito":    ["propunha", "propunhas", "propunha", "propúnhamos", "propúnheis", "propunham"],
            "Futuro do Presente":      ["pro porei", "proporás", "proporá", "proporemos", "proporeis", "proporão"],
            "Futuro do Pretérito":     ["proporia", "proporias", "proporia", "proporíamos", "proporíeis", "proporiam"],
            "Presente do Subjuntivo":  ["proponha", "proponhas", "proponha", "proponhamos", "proponhais", "proponham"],
            "Pretérito Imperfeito do Subjuntivo": ["propusesse", "propusesses", "propusesse", "propuséssemos", "propusésseis", "propusessem"],
            "Futuro do Subjuntivo":    ["propuser", "propuseres", "propuser", "propusermos", "propuserdes", "propuserem"],
            "Imperativo Afirmativo":   ["—", "propõe", "proponha", "proponhamos", "propôde", "proponham"],
        ],
        "repor": [
            "Presente do Indicativo":  ["reponho", "repões", "repõe", "repomos", "repondes", "repõem"],
            "Pretérito Perfeito":      ["repus", "repuseste", "repôs", "repusemos", "repusestes", "repuseram"],
            "Pretérito Imperfeito":    ["repunha", "repunhas", "repunha", "repúnhamos", "repúnheis", "repunham"],
            "Futuro do Presente":      ["reporei", "reporás", "reporá", "reporemos", "reporeis", "reporão"],
            "Futuro do Pretérito":     ["reporia", "reporias", "reporia", "reporíamos", "reporíeis", "reporiam"],
            "Presente do Subjuntivo":  ["reponha", "reponhas", "reponha", "reponhamos", "reponhais", "reponham"],
            "Pretérito Imperfeito do Subjuntivo": ["repusesse", "repusesses", "repusesse", "repuséssemos", "repusésseis", "repusessem"],
            "Futuro do Subjuntivo":    ["repuser", "repuseres", "repuser", "repusermos", "repuserdes", "repuserem"],
            "Imperativo Afirmativo":   ["—", "repõe", "reponha", "reponhamos", "repôde", "reponham"],
        ],
        "supor": [
            "Presente do Indicativo":  ["suponho", "supões", "supõe", "supomos", "supondes", "supõem"],
            "Pretérito Perfeito":      ["supus", "supuseste", "supôs", "supusemos", "supusestes", "supuseram"],
            "Pretérito Imperfeito":    ["supunha", "supunhas", "supunha", "supúnhamos", "supúnheis", "supunham"],
            "Futuro do Presente":      ["suporei", "suporás", "suporá", "suporemos", "suporeis", "suporão"],
            "Futuro do Pretérito":     ["suporia", "suporias", "suporia", "suporíamos", "suporíeis", "suporiam"],
            "Presente do Subjuntivo":  ["suponha", "suponhas", "suponha", "suponhamos", "suponhais", "suponham"],
            "Pretérito Imperfeito do Subjuntivo": ["supusesse", "supusesses", "supusesse", "supuséssemos", "supusésseis", "supusessem"],
            "Futuro do Subjuntivo":    ["supuser", "supuseres", "supuser", "supusermos", "supuserdes", "supuserem"],
            "Imperativo Afirmativo":   ["—", "supõe", "suponha", "suponhamos", "supôde", "suponham"],
        ],

        // ── trazer, caber, valer ──
        "trazer": [
            "Presente do Indicativo":  ["trago", "trazes", "traz", "trazemos", "trazeis", "trazem"],
            "Pretérito Perfeito":      ["trouxe", "trouxeste", "trouxe", "trouxemos", "trouxestes", "trouxeram"],
            "Pretérito Imperfeito":    ["trazia", "trazias", "trazia", "trazíamos", "trazíeis", "traziam"],
            "Futuro do Presente":      ["trarei", "trarás", "trará", "traremos", "trareis", "trarão"],
            "Futuro do Pretérito":     ["traria", "trarias", "traria", "traríamos", "traríeis", "trariam"],
            "Presente do Subjuntivo":  ["traga", "tragas", "traga", "tragamos", "tragais", "tragam"],
            "Pretérito Imperfeito do Subjuntivo": ["trouxesse", "trouxesses", "trouxesse", "trouxéssemos", "trouxésseis", "trouxessem"],
            "Futuro do Subjuntivo":    ["trouxer", "trouxeres", "trouxer", "trouxermos", "trouxerdes", "trouxerem"],
            "Imperativo Afirmativo":   ["—", "traz", "traga", "tragamos", "trazei", "tragam"],
        ],
        "caber": [
            "Presente do Indicativo":  ["caibo", "cabes", "cabe", "cabemos", "cabeis", "cabem"],
            "Pretérito Perfeito":      ["coube", "coubeste", "coube", "coubemos", "coubestes", "couberam"],
            "Pretérito Imperfeito":    ["cabia", "cabias", "cabia", "cabíamos", "cabíeis", "cabiam"],
            "Futuro do Presente":      ["caberei", "caberás", "caberá", "caberemos", "cabereis", "caberão"],
            "Futuro do Pretérito":     ["caberia", "caberias", "caberia", "caberíamos", "caberíeis", "caberiam"],
            "Presente do Subjuntivo":  ["caiba", "caibas", "caiba", "caibamos", "caibais", "caibam"],
            "Pretérito Imperfeito do Subjuntivo": ["coubesse", "coubesses", "coubesse", "coubéssemos", "coubésseis", "coubessem"],
            "Futuro do Subjuntivo":    ["couber", "couberes", "couber", "coubermos", "couberdes", "couberem"],
            "Imperativo Afirmativo":   ["—", "cabe", "caiba", "caibamos", "cabei", "caibam"],
        ],
        "valer": [
            "Presente do Indicativo":  ["valho", "vales", "vale", "valemos", "valeis", "valem"],
            "Pretérito Perfeito":      ["vali", "valeste", "valeu", "valemos", "valestes", "valeram"],
            "Pretérito Imperfeito":    ["valia", "valias", "valia", "valíamos", "valíeis", "valiam"],
            "Futuro do Presente":      ["valerei", "valerás", "valerá", "valeremos", "valereis", "valerão"],
            "Futuro do Pretérito":     ["valeria", "valerias", "valeria", "valeríamos", "valeríeis", "valeriam"],
            "Presente do Subjuntivo":  ["valha", "valhas", "valha", "valhamos", "valhais", "valham"],
            "Pretérito Imperfeito do Subjuntivo": ["valesse", "valesses", "valesse", "valêssemos", "valêsseis", "valessem"],
            "Futuro do Subjuntivo":    ["valer", "valeres", "valer", "valermos", "valerdes", "valerem"],
            "Imperativo Afirmativo":   ["—", "vale", "valha", "valhamos", "valei", "valham"],
        ],

        // ── ler, crer, rir & compounds ──
        "ler": [
            "Presente do Indicativo":  ["leio", "lês", "lê", "lemos", "ledes", "leem"],
            "Pretérito Perfeito":      ["li", "leste", "leu", "lemos", "lestes", "leram"],
            "Pretérito Imperfeito":    ["lia", "lias", "lia", "líamos", "líeis", "liam"],
            "Futuro do Presente":      ["lerei", "lerás", "lerá", "leremos", "lereis", "lerão"],
            "Futuro do Pretérito":     ["leria", "lerias", "leria", "leríamos", "leríeis", "leriam"],
            "Presente do Subjuntivo":  ["leia", "leias", "leia", "leiamos", "leiais", "leiam"],
            "Pretérito Imperfeito do Subjuntivo": ["lesse", "lesses", "lesse", "lêssemos", "lêsseis", "lessem"],
            "Futuro do Subjuntivo":    ["ler", "leres", "ler", "lermos", "lerdes", "lerem"],
            "Imperativo Afirmativo":   ["—", "lê", "leia", "leiamos", "lede", "leiam"],
        ],
        "crer": [
            "Presente do Indicativo":  ["creio", "crês", "crê", "cremos", "credos", "creem"],
            "Pretérito Perfeito":      ["cri", "creste", "creu", "cremos", "crestes", "creram"],
            "Pretérito Imperfeito":    ["cria", "crias", "cria", "críamos", "críeis", "criam"],
            "Futuro do Presente":      ["crerei", "crerás", "crerá", "creremos", "crereis", "crerão"],
            "Futuro do Pretérito":     ["creria", "crerias", "creria", "creríamos", "creríeis", "creriam"],
            "Presente do Subjuntivo":  ["creia", "creias", "creia", "creiamos", "creiais", "creiam"],
            "Pretérito Imperfeito do Subjuntivo": ["cresse", "cresses", "cresse", "crêssemos", "crêsseis", "cressem"],
            "Futuro do Subjuntivo":    ["crer", "creres", "crer", "crermos", "crerdes", "crerem"],
            "Imperativo Afirmativo":   ["—", "crê", "creia", "creiamos", "crede", "creiam"],
        ],
        "rir": [
            "Presente do Indicativo":  ["rio", "ris", "ri", "rimos", "rides", "riem"],
            "Pretérito Perfeito":      ["ri", "riste", "riu", "rimos", "ristes", "riram"],
            "Pretérito Imperfeito":    ["ria", "rias", "ria", "ríamos", "ríeis", "riam"],
            "Futuro do Presente":      ["rirei", "rirás", "rirá", "riremos", "rireis", "rirão"],
            "Futuro do Pretérito":     ["riria", "ririas", "riria", "riríamos", "riríeis", "ririam"],
            "Presente do Subjuntivo":  ["ria", "rias", "ria", "riamos", "riais", "riam"],
            "Pretérito Imperfeito do Subjuntivo": ["risse", "risses", "risse", "ríssemos", "rísseis", "rissem"],
            "Futuro do Subjuntivo":    ["rir", "rires", "rir", "rirmos", "rirdes", "rirem"],
            "Imperativo Afirmativo":   ["—", "ri", "ria", "riamos", "ride", "riam"],
        ],

        // ── ouvir ──
        "ouvir": [
            "Presente do Indicativo":  ["ouço", "ouves", "ouve", "ouvimos", "ouvis", "ouvem"],
            "Pretérito Perfeito":      ["ouvi", "ouviste", "ouviu", "ouvimos", "ouvistes", "ouviram"],
            "Pretérito Imperfeito":    ["ouvia", "ouvias", "ouvia", "ouvíamos", "ouvíeis", "ouviam"],
            "Futuro do Presente":      ["ouvirei", "ouvirás", "ouvirá", "ouviremos", "ouvireis", "ouvirão"],
            "Futuro do Pretérito":     ["ouviria", "ouvirias", "ouviria", "ouviríamos", "ouviríeis", "ouviriam"],
            "Presente do Subjuntivo":  ["ouça", "ouças", "ouça", "ouçamos", "ouçais", "ouçam"],
            "Pretérito Imperfeito do Subjuntivo": ["ouvisse", "ouvisses", "ouvisse", "ouvíssemos", "ouvísseis", "ouvissem"],
            "Futuro do Subjuntivo":    ["ouvir", "ouvires", "ouvir", "ouvirmos", "ouvirdes", "ouvirem"],
            "Imperativo Afirmativo":   ["—", "ouve", "ouça", "ouçamos", "ouvi", "ouçam"],
        ],

        // ── pedir-type (e→i stem, 1p -ço) ──
        "pedir": [
            "Presente do Indicativo":  ["peço", "pedes", "pede", "pedimos", "pedis", "pedem"],
            "Pretérito Perfeito":      ["pedi", "pediste", "pediu", "pedimos", "pedistes", "pediram"],
            "Pretérito Imperfeito":    ["pedia", "pedias", "pedia", "pedíamos", "pedíeis", "pediam"],
            "Futuro do Presente":      ["pedirei", "pedirás", "pedirá", "pediremos", "pedireis", "pedirão"],
            "Futuro do Pretérito":     ["pediria", "pedirias", "pediria", "pediríamos", "pediríeis", "pediriam"],
            "Presente do Subjuntivo":  ["peça", "peças", "peça", "peçamos", "peçais", "peçam"],
            "Pretérito Imperfeito do Subjuntivo": ["pedisse", "pedisses", "pedisse", "pedíssemos", "pedísseis", "pedissem"],
            "Futuro do Subjuntivo":    ["pedir", "pedires", "pedir", "pedirmos", "pedirdes", "pedirem"],
            "Imperativo Afirmativo":   ["—", "pede", "peça", "peçamos", "pedi", "peçam"],
        ],
        "medir": [
            "Presente do Indicativo":  ["meço", "medes", "mede", "medimos", "medis", "medem"],
            "Pretérito Perfeito":      ["medi", "mediste", "mediu", "medimos", "medistes", "mediram"],
            "Pretérito Imperfeito":    ["media", "medias", "media", "medíamos", "medíeis", "mediam"],
            "Futuro do Presente":      ["medirei", "medirás", "medirá", "mediremos", "medireis", "medirão"],
            "Futuro do Pretérito":     ["mediria", "medirias", "mediria", "mediríamos", "mediríeis", "mediriam"],
            "Presente do Subjuntivo":  ["meça", "meças", "meça", "meçamos", "meçais", "meçam"],
            "Pretérito Imperfeito do Subjuntivo": ["medisse", "medisses", "medisse", "medíssemos", "medísseis", "medissem"],
            "Futuro do Subjuntivo":    ["medir", "medires", "medir", "medirmos", "medirdes", "medirem"],
            "Imperativo Afirmativo":   ["—", "mede", "meça", "meçamos", "medi", "meçam"],
        ],
        "impedir": [
            "Presente do Indicativo":  ["impeço", "impedes", "impede", "impedimos", "impedis", "impedem"],
            "Presente do Subjuntivo":  ["impeça", "impeças", "impeça", "impeçamos", "impeçais", "impeçam"],
            "Imperativo Afirmativo":   ["—", "impede", "impeça", "impeçamos", "impedi", "impeçam"],
        ],

        // ── seguir-type (e→i stem, 1p -go) ──
        "seguir": [
            "Presente do Indicativo":  ["sigo", "segues", "segue", "seguimos", "seguis", "seguem"],
            "Pretérito Perfeito":      ["segui", "seguiste", "seguiu", "seguimos", "seguistes", "seguiram"],
            "Pretérito Imperfeito":    ["seguia", "seguias", "seguia", "seguíamos", "seguíeis", "seguiam"],
            "Futuro do Presente":      ["seguirei", "seguirás", "seguirá", "seguiremos", "seguireis", "seguirão"],
            "Futuro do Pretérito":     ["seguiria", "seguirias", "seguiria", "seguiríamos", "seguiríeis", "seguiriam"],
            "Presente do Subjuntivo":  ["siga", "sigas", "siga", "sigamos", "sigais", "sigam"],
            "Pretérito Imperfeito do Subjuntivo": ["seguisse", "seguisses", "seguisse", "seguíssemos", "seguísseis", "seguissem"],
            "Futuro do Subjuntivo":    ["seguir", "seguires", "seguir", "seguirmos", "seguirdes", "seguirem"],
            "Imperativo Afirmativo":   ["—", "segue", "siga", "sigamos", "segui", "sigam"],
        ],
        "conseguir": [
            "Presente do Indicativo":  ["consigo", "consegues", "consegue", "conseguimos", "conseguis", "conseguem"],
            "Presente do Subjuntivo":  ["consiga", "consigas", "consiga", "consigamos", "consigais", "consigam"],
            "Imperativo Afirmativo":   ["—", "consegue", "consiga", "consigamos", "consegui", "consigam"],
        ],
        "perseguir": [
            "Presente do Indicativo":  ["persigo", "persegues", "persegue", "perseguimos", "perseguis", "perseguem"],
            "Presente do Subjuntivo":  ["persiga", "persigas", "persiga", "persigamos", "persigais", "persigam"],
            "Imperativo Afirmativo":   ["—", "persegue", "persiga", "persigamos", "persegui", "persigam"],
        ],

        // ── sentir-type (e→i stem, 1p -to) ──
        "sentir": [
            "Presente do Indicativo":  ["sinto", "sentes", "sente", "sentimos", "sentis", "sentem"],
            "Pretérito Perfeito":      ["senti", "sentiste", "sentiu", "sentimos", "sentistes", "sentiram"],
            "Pretérito Imperfeito":    ["sentia", "sentias", "sentia", "sentíamos", "sentíeis", "sentiam"],
            "Futuro do Presente":      ["sentirei", "sentirás", "sentirá", "sentiremos", "sentireis", "sentirão"],
            "Futuro do Pretérito":     ["sentiria", "sentirias", "sentiria", "sentiríamos", "sentiríeis", "sentiriam"],
            "Presente do Subjuntivo":  ["sinta", "sintas", "sinta", "sintamos", "sintais", "sintam"],
            "Pretérito Imperfeito do Subjuntivo": ["sentisse", "sentisses", "sentisse", "sentíssemos", "sentísseis", "sentissem"],
            "Futuro do Subjuntivo":    ["sentir", "sentires", "sentir", "sentirmos", "sentirdes", "sentirem"],
            "Imperativo Afirmativo":   ["—", "sente", "sinta", "sintamos", "senti", "sintam"],
        ],
        "consentir": [
            "Presente do Indicativo":  ["consinto", "consentes", "consente", "consentimos", "consentis", "consentem"],
            "Presente do Subjuntivo":  ["consinta", "consintas", "consinta", "consintamos", "consintais", "consintam"],
            "Imperativo Afirmativo":   ["—", "consente", "consinta", "consintamos", "consenti", "consintam"],
        ],
        "mentir": [
            "Presente do Indicativo":  ["minto", "mentes", "mente", "mentimos", "mentis", "mentem"],
            "Presente do Subjuntivo":  ["minta", "mintas", "minta", "mintamos", "mintais", "mintam"],
            "Imperativo Afirmativo":   ["—", "mente", "minta", "mintamos", "menti", "mintam"],
        ],
        "servir": [
            "Presente do Indicativo":  ["sirvo", "serves", "serve", "servimos", "servis", "servem"],
            "Presente do Subjuntivo":  ["sirva", "sirvas", "sirva", "sirvamos", "sirvais", "sirvam"],
            "Imperativo Afirmativo":   ["—", "serve", "sirva", "sirvamos", "servi", "sirvam"],
        ],
        "preferir": [
            "Presente do Indicativo":  ["prefiro", "preferes", "prefere", "preferimos", "preferis", "preferem"],
            "Presente do Subjuntivo":  ["prefira", "prefiras", "prefira", "prefiramos", "prefirais", "prefiram"],
            "Imperativo Afirmativo":   ["—", "prefere", "prefira", "prefiramos", "preferi", "prefiram"],
        ],
        "repetir": [
            "Presente do Indicativo":  ["repito", "repetes", "repete", "repetimos", "repetis", "repetem"],
            "Presente do Subjuntivo":  ["repita", "repitas", "repita", "repitamos", "repitais", "repitam"],
            "Imperativo Afirmativo":   ["—", "repete", "repita", "repitamos", "repeti", "repitam"],
        ],
        "vestir": [
            "Presente do Indicativo":  ["visto", "vestes", "veste", "vestimos", "vestis", "vestem"],
            "Presente do Subjuntivo":  ["vista", "vistas", "vista", "vistamos", "vistais", "vistam"],
            "Imperativo Afirmativo":   ["—", "veste", "vista", "vistamos", "vesti", "vistam"],
        ],
        "ferir": [
            "Presente do Indicativo":  ["firo", "feres", "fere", "ferimos", "feris", "ferem"],
            "Presente do Subjuntivo":  ["fira", "firas", "fira", "firamos", "firais", "firam"],
            "Imperativo Afirmativo":   ["—", "fere", "fira", "firamos", "feri", "firam"],
        ],

        // ── dormir-type (o→u stem) ──
        "dormir": [
            "Presente do Indicativo":  ["durmo", "dormes", "dorme", "dormimos", "dormis", "dormem"],
            "Pretérito Perfeito":      ["dormi", "dormiste", "dormiu", "dormimos", "dormistes", "dormiram"],
            "Pretérito Imperfeito":    ["dormia", "dormias", "dormia", "dormíamos", "dormíeis", "dormiam"],
            "Futuro do Presente":      ["dormirei", "dormirás", "dormirá", "dormiremos", "dormireis", "dormirão"],
            "Futuro do Pretérito":     ["dormiria", "dormirias", "dormiria", "dormiríamos", "dormiríeis", "dormiriam"],
            "Presente do Subjuntivo":  ["durma", "durmãs", "durma", "durmamos", "durmais", "durmam"],
            "Pretérito Imperfeito do Subjuntivo": ["dormisse", "dormisses", "dormisse", "dormíssemos", "dormísseis", "dormissem"],
            "Futuro do Subjuntivo":    ["dormir", "dormires", "dormir", "dormirmos", "dormirdes", "dormirem"],
            "Imperativo Afirmativo":   ["—", "dorme", "durma", "durmamos", "dormi", "durmam"],
        ],
        "cobrir": [
            "Presente do Indicativo":  ["cubro", "cobres", "cobre", "cobrimos", "cobris", "cobrem"],
            "Pretérito Perfeito":      ["cobri", "cobriste", "cobriu", "cobrimos", "cobristes", "cobriram"],
            "Presente do Subjuntivo":  ["cubra", "cubras", "cubra", "cubramos", "cubrais", "cubram"],
            "Imperativo Afirmativo":   ["—", "cobre", "cubra", "cubramos", "cobri", "cubram"],
        ],
        "descobrir": [
            "Presente do Indicativo":  ["descubro", "descobres", "descobre", "descobrimos", "descobris", "descobrem"],
            "Presente do Subjuntivo":  ["descubra", "descubras", "descubra", "descubramos", "descubrais", "descubram"],
            "Imperativo Afirmativo":   ["—", "descobre", "descubra", "descubramos", "descobri", "descubram"],
        ],

        // ── fugir-type (u→o stem, 1p -jo) ──
        "fugir": [
            "Presente do Indicativo":  ["fujo", "foges", "foge", "fugimos", "fugis", "fogem"],
            "Pretérito Perfeito":      ["fugi", "fugiste", "fugiu", "fugimos", "fugistes", "fugiram"],
            "Pretérito Imperfeito":    ["fugia", "fugias", "fugia", "fugíamos", "fugíeis", "fugiam"],
            "Futuro do Presente":      ["fugirei", "fugirás", "fugirá", "fugiremos", "fugireis", "fugirão"],
            "Futuro do Pretérito":     ["fugiria", "fugirias", "fugiria", "fugiríamos", "fugiríeis", "fugiriam"],
            "Presente do Subjuntivo":  ["fuja", "fujas", "fuja", "fujamos", "fujais", "fujam"],
            "Pretérito Imperfeito do Subjuntivo": ["fugisse", "fugisses", "fugisse", "fugíssemos", "fugísseis", "fugissem"],
            "Futuro do Subjuntivo":    ["fugir", "fugires", "fugir", "fugirmos", "fugirdes", "fugirem"],
            "Imperativo Afirmativo":   ["—", "foge", "fuja", "fujamos", "fugi", "fujam"],
        ],

        // ── cair, sair ──
        "cair": [
            "Presente do Indicativo":  ["caio", "cais", "cai", "caímos", "caís", "caem"],
            "Pretérito Perfeito":      ["caí", "caíste", "caiu", "caímos", "caístes", "caíram"],
            "Pretérito Imperfeito":    ["caía", "caías", "caía", "caíamos", "caíeis", "caíam"],
            "Futuro do Presente":      ["cairei", "cairás", "cairá", "cairmos", "caireis", "cairão"],
            "Futuro do Pretérito":     ["cairia", "cairias", "cairia", "cairíamos", "cairíeis", "cairiam"],
            "Presente do Subjuntivo":  ["caia", "caias", "caia", "caiamos", "caiais", "caiam"],
            "Pretérito Imperfeito do Subjuntivo": ["caísse", "caísses", "caísse", "caíssemos", "caísseis", "caíssem"],
            "Futuro do Subjuntivo":    ["cair", "caires", "cair", "cairmos", "cairdes", "caírem"],
            "Imperativo Afirmativo":   ["—", "cai", "caia", "caiamos", "caí", "caiam"],
        ],
        "sair": [
            "Presente do Indicativo":  ["saio", "sais", "sai", "saímos", "saís", "saem"],
            "Pretérito Perfeito":      ["saí", "saíste", "saiu", "saímos", "saístes", "saíram"],
            "Pretérito Imperfeito":    ["saía", "saías", "saía", "saíamos", "saíeis", "saíam"],
            "Futuro do Presente":      ["sairei", "sairás", "sairá", "sairemos", "saireis", "sairão"],
            "Futuro do Pretérito":     ["sairia", "sairias", "sairia", "sairíamos", "sairíeis", "sairiam"],
            "Presente do Subjuntivo":  ["saia", "saias", "saia", "saiamos", "saiais", "saiam"],
            "Pretérito Imperfeito do Subjuntivo": ["saísse", "saísses", "saísse", "saíssemos", "saísseis", "saíssem"],
            "Futuro do Subjuntivo":    ["sair", "saires", "sair", "sairmos", "sairdes", "saírem"],
            "Imperativo Afirmativo":   ["—", "sai", "saia", "saiamos", "saí", "saiam"],
        ],

        // ── -uir verbs (construir-type with accent shift) ──
        "construir": [
            "Presente do Indicativo":  ["construo", "constróis", "constrói", "construímos", "construís", "constroem"],
            "Pretérito Perfeito":      ["construí", "construíste", "construiu", "construímos", "construístes", "construíram"],
            "Pretérito Imperfeito":    ["construía", "construías", "construía", "construíamos", "construíeis", "construíam"],
            "Futuro do Presente":      ["construirei", "construirás", "construirá", "construiremos", "construireis", "construirão"],
            "Futuro do Pretérito":     ["construiria", "construirias", "construiria", "construiríamos", "construiríeis", "construiriam"],
            "Presente do Subjuntivo":  ["construa", "construas", "construa", "construamos", "construais", "construam"],
            "Pretérito Imperfeito do Subjuntivo": ["construísse", "construísses", "construísse", "construíssemos", "construísseis", "construíssem"],
            "Futuro do Subjuntivo":    ["construir", "construíres", "construir", "construirmos", "construirdes", "construírem"],
            "Imperativo Afirmativo":   ["—", "constrói", "construa", "construamos", "construí", "construam"],
        ],
        "destruir": [
            "Presente do Indicativo":  ["destruo", "destróis", "destrói", "destruímos", "destruís", "destroem"],
            "Presente do Subjuntivo":  ["destrua", "destruas", "destrua", "destruamos", "destruais", "destruam"],
            "Imperativo Afirmativo":   ["—", "destrói", "destrua", "destruamos", "destruí", "destruam"],
        ],
        "incluir": [
            "Presente do Indicativo":  ["incluo", "incluis", "inclui", "incluímos", "incluís", "incluem"],
            "Pretérito Perfeito":      ["incluí", "incluíste", "incluiu", "incluímos", "incluístes", "incluíram"],
            "Pretérito Imperfeito":    ["incluía", "incluías", "incluía", "incluíamos", "incluíeis", "incluíam"],
            "Presente do Subjuntivo":  ["inclua", "incluas", "inclua", "incluamos", "incluais", "incluam"],
            "Imperativo Afirmativo":   ["—", "inclui", "inclua", "incluamos", "incluí", "incluam"],
        ],
        "contribuir": [
            "Presente do Indicativo":  ["contribuo", "contribuis", "contribui", "contribuímos", "contribuís", "contribuem"],
            "Presente do Subjuntivo":  ["contribua", "contribuas", "contribua", "contribuamos", "contribuais", "contribuam"],
            "Imperativo Afirmativo":   ["—", "contribui", "contribua", "contribuamos", "contribuí", "contribuam"],
        ],
        "diminuir": [
            "Presente do Indicativo":  ["diminuo", "diminuis", "diminui", "diminuímos", "diminuís", "diminuem"],
            "Presente do Subjuntivo":  ["diminua", "diminuas", "diminua", "diminuamos", "diminuais", "diminuam"],
            "Imperativo Afirmativo":   ["—", "diminui", "diminua", "diminuamos", "diminuí", "diminuam"],
        ],

        // ── -uzir verbs (conduzir, produzir, traduzir) — z→ç in 1p & subj ──
        "conduzir": [
            "Presente do Indicativo":  ["conduzo", "conduzes", "conduz", "conduzimos", "conduzis", "conduzem"],
            "Presente do Subjuntivo":  ["conduza", "conduzas", "conduza", "conduzamos", "conduzais", "conduzam"],
            "Imperativo Afirmativo":   ["—", "conduz", "conduza", "conduzamos", "conduzi", "conduzam"],
        ],
        "produzir": [
            "Presente do Indicativo":  ["produzo", "produzes", "produz", "produzimos", "produzis", "produzem"],
            "Presente do Subjuntivo":  ["produza", "produzas", "produza", "produzamos", "produzais", "produzam"],
            "Imperativo Afirmativo":   ["—", "produz", "produza", "produzamos", "produzi", "produzam"],
        ],
        "traduzir": [
            "Presente do Indicativo":  ["traduzo", "traduzes", "traduz", "traduzimos", "traduzis", "traduzem"],
            "Presente do Subjuntivo":  ["traduza", "traduzas", "traduza", "traduzamos", "traduzais", "traduzam"],
            "Imperativo Afirmativo":   ["—", "traduz", "traduza", "traduzamos", "traduzi", "traduzam"],
        ],

        // ── perder (1p -co, subj -ca) ──
        "perder": [
            "Presente do Indicativo":  ["perco", "perdes", "perde", "perdemos", "perdeis", "perdem"],
            "Pretérito Perfeito":      ["perdi", "perdeste", "perdeu", "perdemos", "perdestes", "perderam"],
            "Pretérito Imperfeito":    ["perdia", "perdias", "perdia", "perdíamos", "perdíeis", "perdiam"],
            "Futuro do Presente":      ["perderei", "perderás", "perderá", "perderemos", "perdereis", "perderão"],
            "Futuro do Pretérito":     ["perderia", "perderias", "perderia", "perderíamos", "perderíeis", "perderiam"],
            "Presente do Subjuntivo":  ["perca", "percãs", "perca", "percamos", "percais", "percam"],
            "Pretérito Imperfeito do Subjuntivo": ["perdesse", "perdesses", "perdesse", "perdêssemos", "perdêsseis", "perdessem"],
            "Futuro do Subjuntivo":    ["perder", "perderes", "perder", "perdermos", "perderdes", "perderem"],
            "Imperativo Afirmativo":   ["—", "perde", "perca", "percamos", "perdei", "percam"],
        ],

        // ── -cer/-cir pattern (c→ç in 1p & subj) ──
        "conhecer": [
            "Presente do Indicativo":  ["conheço", "conheces", "conhece", "conhecemos", "conheceis", "conhecem"],
            "Presente do Subjuntivo":  ["conheça", "conheças", "conheça", "conheçamos", "conheçais", "conheçam"],
            "Imperativo Afirmativo":   ["—", "conhece", "conheça", "conheçamos", "conhecei", "conheçam"],
        ],
        "aparecer": [
            "Presente do Indicativo":  ["apareço", "apareces", "aparece", "aparecemos", "apareceis", "aparecem"],
            "Presente do Subjuntivo":  ["apareça", "apareças", "apareça", "apareçamos", "apareçais", "apareçam"],
            "Imperativo Afirmativo":   ["—", "aparece", "apareça", "apareçamos", "aparecei", "apareçam"],
        ],
        "crescer": [
            "Presente do Indicativo":  ["cresço", "cresces", "cresce", "crescemos", "cresceis", "crescem"],
            "Presente do Subjuntivo":  ["cresça", "cresças", "cresça", "cresçamos", "cresçais", "cresçam"],
            "Imperativo Afirmativo":   ["—", "cresce", "cresça", "cresçamos", "crescei", "cresçam"],
        ],
        "descer": [
            "Presente do Indicativo":  ["desço", "desces", "desce", "descemos", "desceis", "descem"],
            "Presente do Subjuntivo":  ["desça", "desças", "desça", "desçamos", "desçais", "desçam"],
            "Imperativo Afirmativo":   ["—", "desce", "desça", "desçamos", "descei", "desçam"],
        ],
        "esquecer": [
            "Presente do Indicativo":  ["esqueço", "esqueces", "esquece", "esquecemos", "esqueceis", "esquecem"],
            "Presente do Subjuntivo":  ["esqueça", "esqueças", "esqueça", "esqueçamos", "esqueçais", "esqueçam"],
            "Imperativo Afirmativo":   ["—", "esquece", "esqueça", "esqueçamos", "esquecei", "esqueçam"],
        ],
        "merecer": [
            "Presente do Indicativo":  ["mereço", "mereces", "merece", "merecemos", "mereceis", "merecem"],
            "Presente do Subjuntivo":  ["mereça", "mereças", "mereça", "mereçamos", "mereçais", "mereçam"],
            "Imperativo Afirmativo":   ["—", "merece", "mereça", "mereçamos", "merecei", "mereçam"],
        ],
        "nascer": [
            "Presente do Indicativo":  ["nasço", "nascês", "nasce", "nascemos", "nasceis", "nascem"],
            "Presente do Subjuntivo":  ["nasça", "nasças", "nasça", "nasçamos", "nasçais", "nasçam"],
            "Imperativo Afirmativo":   ["—", "nasce", "nasça", "nasçamos", "nascei", "nasçam"],
        ],
        "obedecer": [
            "Presente do Indicativo":  ["obedeço", "obedeces", "obedece", "obedecemos", "obedeceis", "obedecem"],
            "Presente do Subjuntivo":  ["obedeça", "obedeças", "obedeça", "obedeçamos", "obedeçais", "obedeçam"],
            "Imperativo Afirmativo":   ["—", "obedece", "obedeça", "obedeçamos", "obedecei", "obedeçam"],
        ],
        "oferecer": [
            "Presente do Indicativo":  ["ofereço", "ofereces", "oferece", "oferecemos", "ofereceis", "oferecem"],
            "Presente do Subjuntivo":  ["ofereça", "ofereças", "ofereça", "ofereçamos", "ofereçais", "ofereçam"],
            "Imperativo Afirmativo":   ["—", "oferece", "ofereça", "ofereçamos", "oferecei", "ofereçam"],
        ],
        "parecer": [
            "Presente do Indicativo":  ["pareço", "pareces", "parece", "parecemos", "pareceis", "parecem"],
            "Presente do Subjuntivo":  ["pareça", "pareças", "pareça", "pareçamos", "pareçais", "pareçam"],
            "Imperativo Afirmativo":   ["—", "parece", "pareça", "pareçamos", "parecei", "pareçam"],
        ],
        "permanecer": [
            "Presente do Indicativo":  ["permaneço", "permaneces", "permanece", "permanecemos", "permaneceis", "permanecem"],
            "Presente do Subjuntivo":  ["permaneça", "permaneças", "permaneça", "permaneçamos", "permaneçais", "permaneçam"],
            "Imperativo Afirmativo":   ["—", "permanece", "permaneça", "permaneçamos", "permanecei", "permaneçam"],
        ],
        "pertencer": [
            "Presente do Indicativo":  ["pertenço", "pertences", "pertence", "pertencemos", "pertenceis", "pertencem"],
            "Presente do Subjuntivo":  ["pertença", "pertenças", "pertença", "pertençamos", "pertençais", "pertençam"],
            "Imperativo Afirmativo":   ["—", "pertence", "pertença", "pertençamos", "pertencei", "pertençam"],
        ],
        "agradecer": [
            "Presente do Indicativo":  ["agradeço", "agradeces", "agradece", "agradecemos", "agradeceis", "agradecem"],
            "Presente do Subjuntivo":  ["agradeça", "agradeças", "agradeça", "agradeçamos", "agradeçais", "agradeçam"],
            "Imperativo Afirmativo":   ["—", "agradece", "agradeça", "agradeçamos", "agradecei", "agradeçam"],
        ],
        "enriquecer": [
            "Presente do Indicativo":  ["enriqueço", "enriqueces", "enriquece", "enriquecemos", "enriqueceis", "enriquecem"],
            "Presente do Subjuntivo":  ["enriqueça", "enriqueças", "enriqueça", "enriqueçamos", "enriqueçais", "enriqueçam"],
            "Imperativo Afirmativo":   ["—", "enriquece", "enriqueça", "enriqueçamos", "enriquecei", "enriqueçam"],
        ],

        // ── -ger/-gir pattern (g→j in 1p & subj) ──
        "agir": [
            "Presente do Indicativo":  ["ajo", "ages", "age", "agimos", "agis", "agem"],
            "Presente do Subjuntivo":  ["aja", "ajas", "aja", "ajamos", "ajais", "ajam"],
            "Imperativo Afirmativo":   ["—", "age", "aja", "ajamos", "agi", "ajam"],
        ],
        "dirigir": [
            "Presente do Indicativo":  ["dirijo", "diriges", "dirige", "dirigimos", "dirigis", "dirigem"],
            "Presente do Subjuntivo":  ["dirija", "dirijas", "dirija", "dirijamos", "dirijais", "dirijam"],
            "Imperativo Afirmativo":   ["—", "dirige", "dirija", "dirijamos", "dirigi", "dirijam"],
        ],
        "corrigir": [
            "Presente do Indicativo":  ["corrijo", "corriges", "corrige", "corrigimos", "corrigis", "corrigem"],
            "Presente do Subjuntivo":  ["corrija", "corrijas", "corrija", "corrijamos", "corrijais", "corrijam"],
            "Imperativo Afirmativo":   ["—", "corrige", "corrija", "corrijamos", "corrigi", "corrijam"],
        ],
        "exigir": [
            "Presente do Indicativo":  ["exijo", "exiges", "exige", "exigimos", "exigis", "exigem"],
            "Presente do Subjuntivo":  ["exija", "exijas", "exija", "exijamos", "exijais", "exijam"],
            "Imperativo Afirmativo":   ["—", "exige", "exija", "exijamos", "exigi", "exijam"],
        ],
        "restringir": [
            "Presente do Indicativo":  ["restrinjo", "restringes", "restringe", "restringimos", "restringis", "restringem"],
            "Presente do Subjuntivo":  ["restrinja", "restrinjas", "restrinja", "restrinjamos", "restrinjais", "restrinjam"],
            "Imperativo Afirmativo":   ["—", "restringe", "restrinja", "restrinjamos", "restringi", "restrinjam"],
        ],

        // ── escolher, colher (irregular 1p -ho) ──
        "escolher": [
            "Presente do Indicativo":  ["escolho", "escolhes", "escolhe", "escolhemos", "escolheis", "escolhem"],
            "Presente do Subjuntivo":  ["escolha", "escolhas", "escolha", "escolhamos", "escolhais", "escolham"],
        ],
        "colher": [
            "Presente do Indicativo":  ["colho", "colhes", "colhe", "colhemos", "colheis", "colhem"],
            "Presente do Subjuntivo":  ["colha", "colhas", "colha", "colhamos", "colhais", "colham"],
        ],

        // ── extra common ──
        "reaver": [
            "Presente do Indicativo":  ["reouve", "reouves", "reouve", "reavermos", "reaverdes", "reouverem"],
            "Presente do Subjuntivo":  ["reouveja", "reouvejas", "reouveja", "reouvejamos", "reouvejais", "reouvejam"],
        ],
        "requerer": [
            "Presente do Indicativo":  ["requeiro", "requeres", "requer", "requeremos", "requereis", "requerem"],
            "Presente do Subjuntivo":  ["requeira", "requeiras", "requeira", "requeiramos", "requeirais", "requeiram"],
        ],
    ]

    static let arEndings: [String: [String]] = [
        "Presente do Indicativo":                       ["o", "as", "a", "amos", "ais", "am"],
        "Pretérito Perfeito":                           ["ei", "aste", "ou", "amos", "astes", "aram"],
        "Pretérito Imperfeito":                         ["ava", "avas", "ava", "ávamos", "áveis", "avam"],
        "Pretérito Mais-que-Perfeito":                  ["ara", "aras", "ara", "áramos", "áreis", "aram"],
        "Futuro do Presente":                           ["arei", "arás", "ará", "aremos", "areis", "arão"],
        "Futuro do Pretérito":                          ["aria", "arias", "aria", "aríamos", "aríeis", "ariam"],
        "Presente do Subjuntivo":                       ["e", "es", "e", "emos", "eis", "em"],
        "Pretérito Imperfeito do Subjuntivo":           ["asse", "asses", "asse", "ássemos", "ásseis", "assem"],
        "Futuro do Subjuntivo":                         ["ar", "ares", "ar", "armos", "ardes", "arem"],
        "Imperativo Afirmativo":                        ["—", "a", "e", "emos", "ai", "em"],
    ]

    static let erEndings: [String: [String]] = [
        "Presente do Indicativo":                       ["o", "es", "e", "emos", "eis", "em"],
        "Pretérito Perfeito":                           ["i", "este", "eu", "emos", "estes", "eram"],
        "Pretérito Imperfeito":                         ["ia", "ias", "ia", "íamos", "íeis", "iam"],
        "Pretérito Mais-que-Perfeito":                  ["era", "eras", "era", "êramos", "êreis", "eram"],
        "Futuro do Presente":                           ["erei", "erás", "erá", "eremos", "ereis", "erão"],
        "Futuro do Pretérito":                          ["eria", "erias", "eria", "eríamos", "eríeis", "eriam"],
        "Presente do Subjuntivo":                       ["a", "as", "a", "amos", "ais", "am"],
        "Pretérito Imperfeito do Subjuntivo":           ["esse", "esses", "esse", "êssemos", "êsseis", "essem"],
        "Futuro do Subjuntivo":                         ["er", "eres", "er", "ermos", "erdes", "erem"],
        "Imperativo Afirmativo":                        ["—", "e", "a", "amos", "ei", "am"],
    ]

    static let irEndings: [String: [String]] = [
        "Presente do Indicativo":                       ["o", "es", "e", "imos", "is", "em"],
        "Pretérito Perfeito":                           ["i", "iste", "iu", "imos", "istes", "iram"],
        "Pretérito Imperfeito":                         ["ia", "ias", "ia", "íamos", "íeis", "iam"],
        "Pretérito Mais-que-Perfeito":                  ["ira", "iras", "ira", "íramos", "íreis", "iram"],
        "Futuro do Presente":                           ["irei", "irás", "irá", "iremos", "ireis", "irão"],
        "Futuro do Pretérito":                          ["iria", "irias", "iria", "iríamos", "iríeis", "iriam"],
        "Presente do Subjuntivo":                       ["a", "as", "a", "amos", "ais", "am"],
        "Pretérito Imperfeito do Subjuntivo":           ["isse", "isses", "isse", "íssemos", "ísseis", "issem"],
        "Futuro do Subjuntivo":                         ["ir", "ires", "ir", "irmos", "irdes", "irem"],
        "Imperativo Afirmativo":                        ["—", "e", "a", "amos", "i", "am"],
    ]

    public static func conjugate(_ verb: String, english: String = "") -> VerbConjugation? {
        let v = verb.lowercased().trimmingCharacters(in: .whitespaces)

        if let irregular = irregularVerbs[v] {
            let tenses = tenseOrder.compactMap { name -> TenseGroup? in
                guard let forms = irregular[name] else { return nil }
                return TenseGroup(name: name, forms: zip(pronouns, forms).map { ConjugationForm(pronoun: $0, form: $1) })
            }
            return VerbConjugation(infinitive: v, english: english, tenses: tenses)
        }

        guard v.hasSuffix("ar") || v.hasSuffix("er") || v.hasSuffix("ir") else { return nil }

        let stem: String
        let endings: [String: [String]]
        if v.hasSuffix("ar") {
            stem = String(v.dropLast(2))
            endings = arEndings
        } else if v.hasSuffix("er") {
            stem = String(v.dropLast(2))
            endings = erEndings
        } else {
            stem = String(v.dropLast(2))
            endings = irEndings
        }

        let tenses = tenseOrder.compactMap { name -> TenseGroup? in
            guard let endForms = endings[name] else { return nil }
            let forms = zip(pronouns, endForms).map { ConjugationForm(pronoun: $0, form: stem + $1) }
            return TenseGroup(name: name, forms: forms)
        }
        return VerbConjugation(infinitive: v, english: english, tenses: tenses)
    }
}
