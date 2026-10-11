"""Synthetic XML checks for the local AMI segment exporter."""

import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

from ami_transcript_lines import NITE, referenced_elements, segment_text, transcript_lines


class AMITranscriptLinesTests(unittest.TestCase):
    def test_punctuation_attaches_and_nonwords_are_excluded(self):
        elements = [
            ET.fromstring('<w>um</w>'), ET.fromstring('<vocalsound type="laugh"/>'),
            ET.fromstring('<w punc="true">,</w>'), ET.fromstring('<w>hello</w>'),
            ET.fromstring('<w punc="true">.</w>'),
        ]
        self.assertEqual(segment_text(elements), 'um, hello.')

    def test_leading_marks_do_not_become_words(self):
        marks = [ET.fromstring('<w punc="true">.</w>')]
        self.assertEqual(segment_text(marks), "")
        self.assertEqual(segment_text(marks + [ET.fromstring("<w>hello</w>")]), ".hello")

    def test_ranges_use_inclusive_element_indices(self):
        entries = [ET.fromstring(f'<w>{word}</w>') for word in ['one', 'two', 'three']]
        words = {'sample.words.xml': entries}
        positions = {'sample.words.xml': {'a': 0, 'b': 1, 'c': 2}}
        result = referenced_elements('sample.words.xml#id(a)..id(b)', words, positions)
        self.assertEqual([entry.text for entry in result], ['one', 'two'])
        single = referenced_elements('sample.words.xml#id(c)', words, positions)
        self.assertEqual([entry.text for entry in single], ['three'])
        with self.assertRaises(ValueError):
            referenced_elements('sample.words.xml#id(c)..id(a)', words, positions)
        with self.assertRaises(ValueError):
            referenced_elements('not-a-reference', words, positions)

    def test_segments_keep_word_order_and_skip_nonverbal_segments(self):
        memory = io.BytesIO()
        with zipfile.ZipFile(memory, 'w') as archive:
            archive.writestr('words/sample.words.xml', f'''<root xmlns:n="{NITE[1:-1]}">
                <w n:id="a">hello</w><w n:id="b" punc="true">.</w>
                <vocalsound n:id="c" type="laugh"/></root>''')
            archive.writestr('segments/sample.segments.xml', f'''<root xmlns:n="{NITE[1:-1]}">
                <segment><n:child href="sample.words.xml#id(a)..id(b)"/></segment>
                <segment><n:child href="sample.words.xml#id(c)"/></segment></root>''')
        with zipfile.ZipFile(memory) as archive:
            self.assertEqual(list(transcript_lines(archive)), ['hello.'])

    def test_cli_rejects_output_inside_repository(self):
        script = Path(__file__).with_name("ami_transcript_lines.py")
        output = script.parent.parent / "reference-must-not-be-written.txt"
        result = subprocess.run(
            [sys.executable, str(script), "missing.zip", str(output)],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("Reference text must stay outside the repository", result.stderr)
        self.assertFalse(output.exists())

    def test_cli_rejects_another_git_repository(self):
        script = Path(__file__).with_name("ami_transcript_lines.py")
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            (repository / ".git").mkdir()
            output = repository / "local-reference.txt"
            result = subprocess.run(
                [sys.executable, str(script), "missing.zip", str(output)],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("Reference text must stay outside the repository", result.stderr)
            self.assertFalse(output.exists())

    def test_empty_and_multiline_words_fail_closed(self):
        for xml in ['<w/>', '<w>first\nsecond</w>']:
            with self.assertRaises(ValueError):
                segment_text([ET.fromstring(xml)])


if __name__ == '__main__':
    unittest.main()
