# Show HN (draft)

Post on a **US weekday morning**, roughly 7 to 9 am US Eastern, which is
around midnight to 2 am in Sydney. Tuesday to Thursday is usual. The link
goes in the URL field, the text below goes in the first comment. Stay up for
the first few hours to answer questions; replies matter more than the post.

HN rules worth knowing: the product has to be something people can try (it
is, it's free), don't ask friends to upvote, and don't post it twice.

---

## Title

Show HN: Archipic, a private photo archive for architects (iOS)

(Under 80 characters. Alternative: "Show HN: I'm an architect and built a
private photo journal for buildings")

## URL

https://apps.apple.com/app/id6777989742

## First comment

I'm an architect. Like most people in the profession, I photograph buildings
all the time: a façade on a walk, a joint at an exhibition, a plan in a book.
Those photos ended up in the camera roll between receipts and family
pictures, and I could rarely find one when I needed it. So I learned to
program and built the tool I wanted. Archipic is the result. It's free, on
iPhone and iPad.

The core idea is a small, fixed vocabulary instead of free-form tags. Every
photo is one of three types: Building (the whole thing), Element (a part of
it, such as a stair, a window or a joint) or Graphic (a flat reference: a
drawing, a plan, a book page). Each type has a short list of fields, picked
with buttons, never typed. Filing a photo takes about two taps, which makes it
usable on a pavement. The vocabulary is fixed because free keywords drift:
"stair", "stairs", "staircase" and "steps" end up as four tags. A closed list
is what keeps an archive searchable years later.

Tags the user chooses and tags the software guesses are stored separately and
never merged. On-device Vision suggests a type and reads the title, author and
year off a book page or wall label, but a suggestion only becomes a tag when
you confirm it.

Privacy was the other constraint. There's no account, no analytics, no ads and
no third-party SDK, and no server of mine. Photos live in SwiftData and sync
through the user's own iCloud (CloudKit private database), which I can't read.
The App Store privacy label is "Data Not Collected". The app is about 3 MB.

Other things it does: a native camera (grid, level, aspect guides, film-style
colour looks, video), a share-sheet extension for saving images from other
apps, a Shortcuts/Action Button capture action, IPTC/XMP export so tags open in
Lightroom and Bridge, and "Boards", which lay out a selection as a print-ready
B1 poster or an A4 journal PDF.

It's English-only for now, iOS 17 and up. I'd like to hear what's confusing,
and from anyone who keeps a visual archive of any kind: how do you organise
it?

---

Notes for Sami:
- The personal lines (why you started, what you photograph) are a starting
  point. Replace them with your own specifics; they're what makes a Show HN
  read as genuine.
- Every claim above is true of 1.4. If you mention how the app started (for
  example an earlier web version), add it in your own words; it's the kind of
  detail HN readers ask about.
- Likely questions: Android (no), a Mac app (runs on Apple silicon Macs as an
  iPad app), export of the whole archive, why not just use Apple Photos
  albums or Lightroom keywords. Short honest answers work best.
