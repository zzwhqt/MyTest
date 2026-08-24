#!/usr/bin/env python3
"""Build the bundled bank from the one supported Guangdong exam PDF layout."""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from pypdf import PdfReader


QUESTION_MARKER = re.compile(r"(?m)(?:^|\n)[\s　]*(\d{1,3})\s*[\.．、][\s]*")
PAGE_FOOTER = re.compile(r"第\s*\d+\s*页\s*共\s*\d+\s*页")


def tidy(value: str) -> str:
    value = value.replace("\u3000", " ").replace("\r", "\n")
    value = re.sub(r"[ \t]+", " ", value)
    value = re.sub(r"\n{3,}", "\n\n", value)
    return value.strip()


def blocks(path: Path) -> list[dict]:
    reader = PdfReader(str(path))
    combined = ""
    offsets: list[tuple[int, int]] = []
    for page_index, page in enumerate(reader.pages):
        offsets.append((len(combined), page_index))
        text = PAGE_FOOTER.sub("", page.extract_text() or "")
        combined += text + "\n"

    accepted: list[tuple[int, int, int]] = []
    expected = 1
    for match in QUESTION_MARKER.finditer(combined):
        if int(match.group(1)) != expected:
            continue
        accepted.append((expected, match.start(), match.end()))
        expected += 1
        if expected == 101:
            break

    result = []
    for index, (number, start, content_start) in enumerate(accepted):
        end = accepted[index + 1][1] if index + 1 < len(accepted) else len(combined)
        page_index = max(page for offset, page in offsets if offset <= start)
        result.append({"number": number, "body": tidy(combined[content_start:end]), "page": page_index})
    return result


def parse_question(body: str) -> tuple[str, list[str]]:
    markers = []
    cursor = 0
    for letter in "ABCD":
        match = re.search(rf"(?m)(?:^|\n)[\s　]*{letter}[\.．][\s]*", body[cursor:])
        if not match:
            break
        start = cursor + match.start()
        end = cursor + match.end()
        markers.append((letter, start, end))
        cursor = end

    if len(markers) != 4:
        return tidy(body), list("ABCD")

    stem = tidy(body[: markers[0][1]])
    options = []
    for index, (letter, _, start) in enumerate(markers):
        end = markers[index + 1][1] if index + 1 < 4 else len(body)
        option = tidy(body[start:end])
        if index == 3:
            option = re.sub(r"\n第[一二三四五六七八九十]+部分[\s\S]*$", "", option).strip()
        options.append(f"{letter}. {option or letter}")
    return stem, options


def parse_answer(body: str) -> tuple[str, str]:
    explicit = re.search(r"【答案】\s*([A-D])", body)
    fallback = re.search(r"正确选项是\s*([A-D])", body)
    answer = explicit.group(1) if explicit else fallback.group(1) if fallback else ""
    explanation_match = re.search(r"解析[：:]", body)
    explanation = tidy(body[explanation_match.end() :] if explanation_match else body)
    return answer, explanation or "本题解析见原 PDF。"


def build(question_pdf: Path, answer_pdf: Path) -> dict:
    question_blocks = blocks(question_pdf)
    answer_blocks = blocks(answer_pdf)
    if len(question_blocks) != 100 or len(answer_blocks) != 100:
        raise RuntimeError(f"expected 100 blocks, got questions={len(question_blocks)} answers={len(answer_blocks)}")

    visual_pages = {6, 8, 9, 10, 11, 12, 17, 18, 19, 20, 21, 22, 24, 25, 26}
    answers = {block["number"]: parse_answer(block["body"]) for block in answer_blocks}
    answer_questions = {
        block["number"]: parse_question(block["body"].split("【答案】", 1)[0])
        for block in answer_blocks
    }

    questions = []
    for source in question_blocks:
        number = source["number"]
        stem, options = answer_questions[number]
        answer, explanation = answers[number]
        if answer not in "ABCD" or len(options) != 4 or not stem:
            raise RuntimeError(f"invalid parsed question {number}")
        questions.append(
            {
                "id": number,
                "stem": stem,
                "options": options,
                "answer": answer,
                "explanation": explanation,
                "sourcePage": source["page"],
                "hasVisual": source["page"] + 1 in visual_pages,
            }
        )

    return {
        "title": "2020 广东省公务员行测（县级）",
        "importedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "questions": questions,
    }


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: build_bank.py QUESTION.pdf ANSWER.pdf OUTPUT.json")
    output = Path(sys.argv[3])
    output.write_text(json.dumps(build(Path(sys.argv[1]), Path(sys.argv[2])), ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"PASS questions=100 output={output}")


if __name__ == "__main__":
    main()
