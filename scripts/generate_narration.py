import asyncio
import os
import subprocess
import edge_tts

ffmpeg_exe = r'C:\Users\krish\AppData\Local\Programs\Python\Python312\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe'
os.makedirs('narration_audio', exist_ok=True)

VOICE = "en-US-AndrewNeural"

scripts = [
    {
        'id': 'seg1_join',
        'rate': '+0%',
        'text': 'Welcome to DabHousie, the real-time multiplayer Tambola experience! In this walkthrough, we will join a live party room using a 6-digit invite code. Enter your room code, confirm your player nickname, and tap Register to get your unique ticket.'
    },
    {
        'id': 'seg2_lobby',
        'rate': '+15%',
        'text': 'Your seat is confirmed, and the live game room opens automatically.'
    },
    {
        'id': 'seg3_gameplay',
        'rate': '+0%',
        'text': 'The game begins! Numbers drawn by the automated caller appear on the digital board with caller audio and history. When a number is called that matches your 3 by 9 ticket, tap the box to dab it. The interface provides instant visual feedback in real-time.'
    },
    {
        'id': 'seg4_fastforward1',
        'rate': '+5%',
        'text': 'As the game progresses, other players compete simultaneously. Maya just claimed Early 5!'
    },
    {
        'id': 'seg5_pattern_mismatch',
        'rate': '+0%',
        'text': 'What happens if you claim a pattern too early? DabHousie protects players with instant validation, politely alerting you that your pattern is incomplete so fair play is always maintained.'
    },
    {
        'id': 'seg6_fastforward2',
        'rate': '+5%',
        'text': 'The caller continues drawing numbers, and the ticket keeps filling up.'
    },
    {
        'id': 'seg7_bogey_and_unmark',
        'rate': '+0%',
        'text': 'If you accidentally mark an uncalled number and attempt a claim, the system detects the bogey claim immediately. Best of all, players can easily fix accidental mistakes—simply tap any marked number again to unmark it!'
    },
    {
        'id': 'seg8_pre_win',
        'rate': '+5%',
        'text': 'Back on track, we wait for our winning number call.'
    },
    {
        'id': 'seg9_topline_win',
        'rate': '+0%',
        'text': 'Here comes number 56, completing our top line! We tap Top Line to claim. Verified! Confetti celebration and an official voucher reference code! We have won Top Line against all competing players!'
    },
    {
        'id': 'seg10_race_fullhouse',
        'rate': '+0%',
        'text': 'Players race for the remaining prizes! Priya claims Middle Line, Maya takes Bottom Line, Rohan grabs Four Corners, and Maya seals the Full House as the final numbers roll in!'
    },
    {
        'id': 'seg11_rewards',
        'rate': '+0%',
        'text': 'Game concluded! All your winnings are saved in your personal My Rewards dashboard. Open your verified prize voucher with QR code to present directly to your game host. Fast, fair, and fun — that is DabHousie!'
    }
]

async def gen_all():
    print(f"Generating audio narration with voice: {VOICE}")
    for s in scripts:
        out_mp3 = os.path.join('narration_audio', f"{s['id']}.mp3")
        comm = edge_tts.Communicate(s['text'], VOICE, rate=s['rate'])
        await comm.save(out_mp3)
        cmd = [ffmpeg_exe, '-i', out_mp3]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        dur = 0.0
        for line in res.stderr.splitlines():
            if 'Duration:' in line:
                parts = line.split('Duration:')[1].split(',')[0].strip().split(':')
                dur = float(parts[0])*3600 + float(parts[1])*60 + float(parts[2])
                break
        print(f"  {s['id']}: audio duration = {dur:.2f}s")

if __name__ == '__main__':
    asyncio.run(gen_all())
