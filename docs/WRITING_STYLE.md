# Writing style for this repository and the posts about it

Applies to README, docs, CHANGELOG, release notes, and the blog and LinkedIn posts about SwiftQuantum Core. It is the author's voice, adapted so it never loosens what this package is: a simulator, Clifford circuits up to 127 qubits, an exact dense kernel for small circuits, Stim as the reference. Code comments follow the same facts rules, not the narrative rules.

## 0. Hard rules

- No em dash and no arrow bullets. Use a period, a comma or a new sentence.
- No hype words ("revolutionary", "game changer", "breakthrough") and no borrowed authority ("centuries-proven"). The most that is allowed: "we translated principle X into software".
- Never invent a detail. If it is not verified, leave it out. Never embellish the author's history: no made-up conversations, quotes or anecdotes.
- Say for every feature whether it is quantum or not. A classical algorithm is never called quantum. This package is a classical simulator of quantum circuits, not quantum hardware.
- Numbers are measured and specific (127 qubits, ~25 qubits on an iPhone, the exact test counts), never vague adjectives. Keep the headline numbers to three or fewer per piece.
- Honest limits are part of every piece: what it does not do, what is not guaranteed, what was not tested. Label it "verified, not certified", including for the text itself.
- Do not publish private business facts, partner or investor discussions, offers, or anything the author has not approved. Founding year is 2025 only. A patent is "patent filed", never "holder".

## 1. Voice

- Plain declarative statements. Calm is the strongest tone.
- First person, position stated: "I run SwiftQuantum solo, in Seoul."
- Short punch sentences, used sparingly at the decisive spot. Turn by negation then reversal: "That is not a reason to wait. It is the reason to build."
- Dry humour only as a short parenthetical, rarely.
- Poetic lines only from facts that actually happened.

## 2. Blog structure

1. Title: two declarative sentences, a statement then a personal clause.
2. One italic series line ("Part N of a series. Part N-1: title").
3. Cold open with a scene or event: time, place, a measured detail. Never start with a definition.
4. One bold, childlike root question as a standalone sentence.
5. Trace to the floor: go down the stack layer by layer. Section headers tell the story, never "Background" or "Conclusion".
6. The decisive sentence in bold at the end of a paragraph; other people's lines as block quotes.
7. One section on where the author stands.
8. One etymology of a key word in the second half.
9. An "Honest limits" section.
10. The last line echoes the title or the series catchphrase.
11. Rule, then an italic open-inbox paragraph. Report-style posts end with "Sources and further reading".

LinkedIn: no headers, short paragraphs, the event hook in the first two, "Honest limits:" in the second to last paragraph, an echo line last, 3 to 4 hashtags, under 3,000 characters, no link in the body (first comment instead).

Deliverables per post: English blog md, English LinkedIn md, SEO and tags md. The blog and LinkedIn are English only. A Korean copy is a private working draft and is not committed here.

## 3. Thinking checks (run before writing)

- Ten-year-old test: explain each key concept in simple words. Where it blocks, research again. Never fill the gap by guessing.
- Depth: take one simple-looking claim and go down at least three layers.
- State the premise the piece rests on. Argue against premises, not against people. No framing attacks.
- Put the whole map first (set, then relations, then details). Cut any link the reader would not share.
- If the subject holds a contradiction (for example, exact amplitudes versus a stabilizer tableau that cannot hold a T gate), make the contradiction the spine.
- Look for the shared archetype beneath several items and use it as the structure.
- Price-tag test: would a real user choose this on an ordinary Tuesday?

## 4. AI drafting clause

AI handles the compressible part: search, cross-checking, sourcing, a first draft. The author owns the part that does not compress: understanding, connection, the ten-year-old test and the decision to publish. Every AI output is a draft with its evidence attached. Promoting a statement to published fact, to the repository, or to the author's history happens only after the author has verified it. AI tools make things up, so part of the saved time is spent on verification.

## 5. Pre-publish checklist

- [ ] Zero em dashes and zero arrow bullets (machine check: `grep -nE '—|→' file`)
- [ ] Deliverable set complete; LinkedIn under 3,000 characters with hashtags
- [ ] Cold open is a scene or event; bold root question; Honest limits; etymology; echo ending
- [ ] Every fact about the package matches the README table "What this package is and is not"
- [ ] Every statement about the author is confirmed, nothing embellished
- [ ] Each feature labelled quantum or classical; nothing classical called quantum
- [ ] Headline numbers are three or fewer and measured
- [ ] Ten-year-old test passed; three layers deep; premise stated
- [ ] The piece is marked as a draft until the author approves it
