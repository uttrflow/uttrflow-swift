#!/usr/bin/env python3
"""Synthesise invented names by origin, transcribe them, and write what the recogniser heard.

Every name is invented. Audio is made in a temporary folder at measurement time and deleted.
The output TSV feeds `NameVariantRecallProbe` in `UttrflowDictionaryTests`; see
`Docs/name-variant-recall.md`.
"""

import argparse
import os
import subprocess
import sys
import tempfile

# Fifty invented single-word names per origin group, written as a speaker of that origin might spell them.
NAMES = {
    "Indian": (
        "Aaravesh Bhavitra Chaitresh Dhruvali Eshwanti Gaurangi Hrishant Ilavani Jaivardhan Kavyesh "
        "Lavanshi Madhuvrat Nirmayi Ojasvin Pranithi Raghvesh Saanvika Tejomay Uddhavi Vaishnil "
        "Yashovan Anvitra Brijeshwar Charvika Devanshul Gunjali Harshvin Ishaanvi Jyotsar Kiranmay "
        "Lokeshwin Mrinalika Nakshesh Omkaresh Pallavit Rudraksh Shivanshi Trilochit Urvashan Vedanthi "
        "Abhiraksh Bhoomika Chiranthi Dakshayan Ekanthi Girvesh Himanthi Indravit Kaushalin Manaswit"
    ),
    "East Asian": (
        "Zhaolin Xiuqing Wenhao Jiayue Shuyan Haoming Qiulan Yuzhen Tianrui Mingxuan "
        "Ruoxi Zihan Junhao Xinyi Bowen Kaiqi Lingyun Shaoqing Yichen Huanle "
        "Kazuhiro Takemori Haruyuki Sakurako Tomonari Yoshiaki Mizuhara Kenshiro Ayumika Nobutaka "
        "Ryotaro Shinobu Hikaruko Daisuke Masayori Kotomine Fumihiko Chiharu Tsubasa Yukihana "
        "Minjae Seoyun Jihwan Haneul Dohyun Eunbi Sungmin Yejin Taewoo Soobin"
    ),
    "Slavic": (
        "Zdravko Wieslawa Przemko Boguslav Radomira Svetozar Ljubomira Miroslavek Dobroslav Jaroslavna "
        "Kazimirov Vladimirka Borislavek Stanimira Wojtasik Grzegorzak Szczepanov Dragomirov Velimira Tihomirka "
        "Zbigniewka Ostromir Bozhidara Vsevolodin Yaropolk Rostislavna Mstislavek Lyudmilka Yevgenik Zhivorad "
        "Chestimir Kresimira Dobrawa Slawomirek Bronislavka Tvrtkovic Pribislav Ognjenka Radoslawa Vojislavic "
        "Dragoljuba Miloradek Zlatomira Branimirov Krasimirka Vukashin Ratimira Desislavka Predrag Budimira"
    ),
    "Arabic": (
        "Abdulqadir Khadijah Zayyanah Mutasim Raghidah Thamirah Ghassanah Fawwazi Juwairiyah Muhannadi "
        "Nawwafah Qutaybah Dhakirah Ubaydillah Sulaymaniyah Harithah Shuraihah Zubaydah Khuzaymah Badriyyah "
        "Taqiyuddin Wadhahah Ruqayyat Mu'adhah Jumanahi Sakhrah Dhuha'i Ghufranah Haythamah Lubabah "
        "Abdulmuhsin Nuhaylah Thurayyah Faisaliyah Majidiyyah Khawlahi Rawdhah Qaswarah Zahiyyah Dujanah "
        "Sumayyahi Hamdaniyah Iyadhah Marwaniyah Nusaybah Rafidahi Shaimaah Tawfiqah Yusrahi Zakiyyat"
    ),
    "Romance": (
        "Giancarlino Fiorenzia Gualtiero Ludovichetta Benedettina Jacopetto Graziella Ottaviano Sbrighetti Cesarino "
        "Joaquinita Ximenara Guillerma Rodrigano Esperanzita Iñaquelo Begoñita Xabierra Gonzalito Fuencisla "
        "Thibaultin Gwenaelle Guillemette Enguerrand Aurelienne Ghislaine Jehanot Clotildine Bertrandou Mathurine "
        "Joaozinho Conceicaona Leopoldino Ribamarzinho Adalgisa Felismina Hortensio Gualdino Raimundinha Vasquinho "
        "Ilinca Sorinela Dragulescu Bogdanela Vasilica Floricica Tudorache Mircescu Ionelia Petrisor"
    ),
    "English": (
        "Ashworthy Brackenridge Coldbeck Dunsmoor Elswick Fenwickham Garthwaite Hollingrake Ingleby Kettlewell "
        "Lockhartson Marrowby Netherwood Oakenshaw Pembridgeton Quarrington Ravensworth Stalbridge Thistlewood Underhay "
        "Wetherill Yarborough Ambrosine Bellamina Corisande Delphinia Ermengarde Florimel Gwendolen Hesketh "
        "Isembard Jocelind Kenelmine Lettice Melisende Osbertina Peregrina Rosamunde Sebastiana Tristram "
        "Wilfreda Ysolde Aldwin Brithric Cuthbertine Edwold Godwina Hildreth Leofrida Wynstan"
    ),
}

CARRIER = "Please send the notes to {} before lunch."
VOICES = ("Samantha", "Rishi")


def run(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uttrflow-dev", required=True, help="Path to the built uttrflow-dev binary.")
    parser.add_argument("--out", required=True, help="TSV to write: group, name, voice, heard.")
    parser.add_argument("--voices", default=",".join(VOICES), help="Comma-separated `say` voices.")
    args = parser.parse_args(argv)
    rows = []
    with tempfile.TemporaryDirectory() as scratch:
        wav = os.path.join(scratch, "clip.wav")
        for voice in args.voices.split(","):
            for group, names in NAMES.items():
                for name in names.split():
                    subprocess.run(
                        ["say", "-v", voice, "-o", wav, "--data-format=LEI16@16000", CARRIER.format(name)],
                        check=True)
                    heard = subprocess.run(
                        [args.uttrflow_dev, "transcribe", wav, "--raw", "--language", "en"],
                        check=True, capture_output=True, text=True).stdout.strip().splitlines()
                    text = heard[-1].replace("\t", " ") if heard else ""
                    rows.append((group, name, voice, text))
                    print(f"{voice}\t{group}\t{name}\t{text}", file=sys.stderr)
    with open(args.out, "w", encoding="utf-8") as out:
        for row in rows:
            out.write("\t".join(row) + "\n")


if __name__ == "__main__":
    run()
