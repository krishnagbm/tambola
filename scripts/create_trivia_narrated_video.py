import asyncio
import os
import subprocess

ffmpeg_exe = r'C:\Users\krish\AppData\Local\Programs\Python\Python312\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe'
raw_video = r'C:\Users\krish\Videos\DabHousie_Play_Trivia_Game.mp4'
output_dir = r'C:\dev\Tambola\narration_audio\trivia_run'
final_video = r'C:\Users\krish\Videos\DabHousie_Play_Trivia_Game_Narrated.mp4'

os.makedirs(output_dir, exist_ok=True)

VOICE = "en-US-AndrewNeural"

segments = [
    {
        'id': 'seg01_intro',
        'start_sec': 2.0,
        'rate': '+0%',
        'text': "Welcome to DabHousie, the modern real-time multiplayer Tambola experience! In this live party room, Office Chai and DabHousie Break, six players are competing together across six prize categories, followed by our signature Post-Game Recall Trivia."
    },
    {
        'id': 'seg02_gameplay_autodab',
        'start_sec': 26.0,
        'rate': '+0%',
        'text': "The automated caller begins drawing numbers. Notice the high-definition ticket matrix—every matching called number is automatically identified and marked with real-time emerald green visual feedback."
    },
    {
        'id': 'seg03_early5_win',
        'start_sec': 76.0,
        'rate': '+0%',
        'text': "Number 6 is announced, completing our fifth marked number! The platform validates the ticket instantly, and Aarav claims the first official prize—Early 5!"
    },
    {
        'id': 'seg04_multiplayer_pace',
        'start_sec': 165.0,
        'rate': '+5%',
        'text': "Numbers keep rolling in at a brisk pace. Other players in the room are actively hunting for their winning numbers. Priya secures Four Corners, raising the stakes for the remaining prizes!"
    },
    {
        'id': 'seg05_topline_win',
        'start_sec': 274.0,
        'rate': '+0%',
        'text': "Here comes number 59, completing our entire top row! We tap Top Line to claim—verified! Confetti flies, and Aarav bags his second prize win of the game!"
    },
    {
        'id': 'seg06_fullhouse_conclusion',
        'start_sec': 318.0,
        'rate': '+0%',
        'text': "Liam takes Middle Line, and Maya clinches Bottom Line. Now it all comes down to the grand prize. Rohan calls Full House on number 1! The classic Tambola round concludes!"
    },
    {
        'id': 'seg07_trivia_countdown',
        'start_sec': 340.0,
        'rate': '+0%',
        'text': "Now the real fun begins! DabHousie instantly transitions to Corporate Recall Trivia! Notice the intelligent anti-cheat concealment: ticket numbers and prize boards are locked away to test memory, observation, and focus!"
    },
    {
        'id': 'seg08_question1',
        'start_sec': 355.0,
        'rate': '+0%',
        'text': "Question 1: How many total players checked into the game room today? Aarav recalls six players, answering in just 2.3 seconds for a massive speed bonus of 922 points!"
    },
    {
        'id': 'seg09_question2',
        'start_sec': 371.0,
        'rate': '+0%',
        'text': "Question 2: What was the final number drawn that completed Full House? Aarav locks in number 1, earning another 779 points with lightning-fast recall!"
    },
    {
        'id': 'seg10_question3',
        'start_sec': 387.0,
        'rate': '+5%',
        'text': "Question 3: Which prize pattern was claimed first in the room? The clock ticks rapidly down—speed and nerve are everything in live trivia!"
    },
    {
        'id': 'seg11_question4',
        'start_sec': 402.0,
        'rate': '+5%',
        'text': "Question 4 asks for the total distinct prize winners. A quick guess, and the recall round concludes!"
    },
    {
        'id': 'seg12_podium',
        'start_sec': 417.0,
        'rate': '+0%',
        'text': "The scores are finalized, and the official Trivia Podium is unveiled! With 1,695 points, Aarav is crowned the Observation Champion with the gold medal!"
    },
    {
        'id': 'seg13_review',
        'start_sec': 432.0,
        'rate': '+0%',
        'text': "Players can tap to open the full question and answer review, examining their exact reaction times, correct picks in green, missed answers in red, and detailed point calculations."
    },
    {
        'id': 'seg14_rewards_outro',
        'start_sec': 448.0,
        'rate': '+0%',
        'text': "Finally, opening My Rewards displays verified prize vouchers with scannable QR codes for Top Line and Early 5, ready for instant redemption with the host. Fast, fair, and engaging—that is DabHousie!"
    }
]

def get_duration(file_path):
    cmd = [ffmpeg_exe, '-i', file_path]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for line in res.stderr.splitlines():
        if 'Duration:' in line:
            parts = line.split('Duration:')[1].split(',')[0].strip().split(':')
            return float(parts[0])*3600 + float(parts[1])*60 + float(parts[2])
    return 0.0

async def generate_speech():
    import edge_tts
    print(f"=== Generating 14 Studio Narration Segments with {VOICE} ===")
    for s in segments:
        out_file = os.path.join(output_dir, f"{s['id']}.mp3")
        s['file'] = out_file
        
        # Check if already generated
        if not (os.path.exists(out_file) and os.path.getsize(out_file) > 1000):
            success = False
            for attempt in range(4):
                try:
                    await asyncio.sleep(1.0)
                    comm = edge_tts.Communicate(s['text'], VOICE, rate=s['rate'])
                    await comm.save(out_file)
                    if os.path.exists(out_file) and os.path.getsize(out_file) > 1000:
                        success = True
                        break
                except Exception as e:
                    print(f"    [Retry {attempt+1}/4] {s['id']}: {e}")
                    await asyncio.sleep(2.0 * (attempt + 1))
            if not success:
                raise RuntimeError(f"Failed to generate speech for {s['id']}")
                
        dur = get_duration(out_file)
        s['dur'] = dur
        print(f"  [{s['start_sec']:>5.1f}s] {s['id']}: {dur:.2f}s -> '{s['text'][:60]}...'")

def assemble_narrated_video():
    total_video_dur = get_duration(raw_video)
    print(f"\nSource Video Duration: {total_video_dur:.2f}s")
    
    # Build ffmpeg audio filter complex with adelay and amix
    inputs = ['-i', raw_video]
    filter_parts = []
    
    for i, s in enumerate(segments):
        inputs.extend(['-i', s['file']])
        delay_ms = int(s['start_sec'] * 1000)
        # 1-indexed because input 0 is video
        stream_idx = i + 1
        filter_parts.append(f"[{stream_idx}:a]adelay={delay_ms}|{delay_ms},volume=1.0[a{stream_idx}]")
    
    mix_inputs = ''.join([f"[a{i+1}]" for i in range(len(segments))])
    filter_parts.append(f"{mix_inputs}amix=inputs={len(segments)}:duration=longest:normalize=0[aout]")
    
    filter_complex = ';'.join(filter_parts)
    
    cmd = [
        ffmpeg_exe, '-y',
        *inputs,
        '-filter_complex', filter_complex,
        '-map', '0:v',
        '-map', '[aout]',
        '-c:v', 'copy',
        '-c:a', 'aac',
        '-b:a', '192k',
        '-t', str(total_video_dur),
        final_video
    ]
    
    print("\nMixing narration onto video timeline with FFmpeg...")
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print("FFmpeg error:", res.stderr[-1000:])
        raise RuntimeError("FFmpeg mixing failed")
    
    out_dur = get_duration(final_video)
    print(f"\nSUCCESS! Narrated video created at:")
    print(f"   {final_video}")
    print(f"   Duration: {out_dur:.2f}s ({int(out_dur//60)}m {int(out_dur%60)}s)")

async def main():
    await generate_speech()
    assemble_narrated_video()

if __name__ == '__main__':
    asyncio.run(main())
