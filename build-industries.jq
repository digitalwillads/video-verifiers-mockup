# Compacts a video-idea run's lines.json into the data that industries.html shows.
# Input: the verifier's lines.json (an array of lines). $res: [results.json]. $note: one free-text note line.
def first_capture(s; re): [s | capture(re)][0].w // null;

{
  run_at: ($res[0].run_at // null),
  units: ($res[0].units // null),
  note: (if $note == "" then null else $note end),
  lines: [ .[]
    | (.proof // null) as $proof
    | (if .a.outcome != "PASS" then "A"
       elif .b.outcome != "PASS" then "B"
       elif (.c.outcome // "") == "PASS" then null
       elif ((.c.trace // "") | test("vi-c-beats: no")) then "C-score"
       elif ((.c.trace // "") | test("vi-c-proof: no")) then "C-ai"
       elif ((.c.trace // "") | test("vi-c-read: warning")) then "C-noquery"
       else "C-none" end) as $kind
    | {
        n, line, outcome, kind: $kind, a_p: .a_jev_p,
        reason: (if $kind == null then null
                 elif $kind == "A" then null
                 elif $kind == "B" then first_capture(.b.trace; "vi-b-new: no \\((?<w>.*?)\\) → ")
                 elif $kind == "C-score" then first_capture(.c.trace; "vi-c-beats: no \\((?<w>.*?)\\) → ")
                 elif $kind == "C-ai" then (first_capture(.c.trace; "vi-c-proof: no \\((?<w>.*?)\\) → ") // "" | sub("^Jev says "; "the AI says "))
                 else first_capture(.c.trace; "vi-c-(?:named|read): warning \\((?<w>.*?)\\) → ") end),
        proof: (if $proof then {id: $proof.id, title: $proof.title, channel: $proof.channel, score: $proof.score,
                views: $proof.views, subs: $proof.subscribers, seconds: $proof.seconds, p: $proof.jev_p} else null end),
        others: [ (.candidates // [])[]
                  | select((.jev_p // 0) >= 0.5 and .score >= 3 and .id != ($proof.id // ""))
                  | {id, title, channel, score, views, subs: .subscribers, p: .jev_p} ]
                | sort_by(-.score) | .[0:5]
      } ]
}
