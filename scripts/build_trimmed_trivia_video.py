import asyncio
import os
import subprocess

ffmpeg_exe = r'C:\Users\krish\AppData\Local\Programs\Python\Python312\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe'
raw_video = r'C:\Users\krish\Videos\DabHousie_Play_Trivia_Game.mp4'
final_output = r'C:\Users\krish\Videos\DabHousie_Play_Trivia_Game_Narrated.mp4'
audio_dir = r'C:\dev\Tambola\narration_audio\trivia_trimmed'
temp_clips_dir = r'C:\dev\Tambola\scratch\trivia_trimmed_clips'

os.makedirs(audio_dir, exist_ok=True)
os.makedirs(temp_clips_dir, exist_ok=True)

VOICE = "en-US-AndrewNeural"

clips_config = [
    {
        'id': 'clip01_intro',
        'raw_start': 0.0,
        'raw_end': 17.5,
        'rate': '+0%',
        'text': "Welcome to DabHousie, the modern real-time multiplayer Tambola experience! In this party game, Office Chai and DabHousie Break, six players are competing live across six prize categories, followed by our signature Post-Game Recall Trivia."
    },
    {
        'id': 'clip02_calling_autodab',
        'raw_start': 24.0,
        'raw_end': 46.0,
        'rate': '+0%',
        'text': "The automated host begins calling numbers. Notice our widescreen ticket matrix—every matching called number is automatically identified and dabbed with crisp emerald green visual feedback in real time."
    },
    {
        'id': 'clip03_race_early5',
        'raw_start': 46.0,
        'raw_end': 74.0,
        'rate': '+5%',
        'text': "Numbers roll in at a rapid clip as our ticket fills up, and players race for the first prize of the room."
    },
    {
        'id': 'clip04_early5_win',
        'raw_start': 74.0,
        'raw_end': 86.0,
        'rate': '+0%',
        'text': "Number 6 is drawn, completing our fifth marked number! The platform validates the ticket instantly, and Aarav claims Early 5 against all competing players!"
    },
    {
        'id': 'clip05_ff_midgame',
        'raw_start': 86.0,
        'raw_end': 270.0,
        'rate': '+5%',
        'text': "With Early 5 secured, other players chase the line prizes. Numbers fly by as Priya locks in Four Corners, pushing us closer to our top row!"
    },
    {
        'id': 'clip06_topline_win',
        'raw_start': 270.0,
        'raw_end': 286.0,
        'rate': '+0%',
        'text': "Here comes number 59, completing our entire top row! We tap Top Line to claim—verified! Aarav secures our second official prize win of the game!"
    },
    {
        'id': 'clip07_ff_fullhouse',
        'raw_start': 286.0,
        'raw_end': 338.0,
        'rate': '+0%',
        'text': "Liam takes Middle Line, and Maya clinches Bottom Line. Now it all comes down to the grand prize. Rohan calls Full House on number 1! The main Tambola round concludes!"
    },
    {
        'id': 'clip08_trivia_countdown',
        'raw_start': 338.0,
        'raw_end': 354.0,
        'rate': '+0%',
        'text': "Now the real fun begins! DabHousie immediately transitions to Corporate Recall Trivia! Notice the intelligent anti-cheat concealment: ticket numbers and prize boards are locked away to test memory, observation, and focus!"
    },
    {
        'id': 'clip09_question1',
        'raw_start': 354.0,
        'raw_end': 370.0,
        'rate': '+0%',
        'text': "Question 1: How many total players checked into the game room today? Aarav recalls six players, answering in just 2.3 seconds for a massive speed bonus of 922 points!"
    },
    {
        'id': 'clip10_question2',
        'raw_start': 370.0,
        'raw_end': 385.0,
        'rate': '+0%',
        'text': "Question 2: What was the final number drawn that completed Full House? Aarav locks in number 1, earning another 779 points with lightning-fast recall!"
    },
    {
        'id': 'clip11_ff_questions3_4',
        'raw_start': 385.0,
        'raw_end': 416.0,
        'rate': '+5%',
        'text': "Questions 3 and 4 test players on prize sequence and distinct winners. Under the clock, split-second memory recall is everything!"
    },
    {
        'id': 'clip12_podium',
        'raw_start': 416.0,
        'raw_end': 432.0,
        'rate': '+0%',
        'text': "The scores are finalized, and the official Trivia Podium is unveiled! With 1,695 points, Aarav is crowned the Observation Champion with the gold medal!"
    },
    {
        'id': 'clip13_review',
        'raw_start': 432.0,
        'raw_end': 448.0,
        'rate': '+0%',
        'text': "Players can tap to open the full question and answer review, examining their exact reaction times, correct picks in green, missed answers in red, and detailed point calculations."
    },
    {
        'id': 'clip14_rewards',
        'raw_start': 448.0,
        'raw_end': 456.8,
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
    print(f"=== Generating {len(clips_config)} Audio Clips with {VOICE} ===")
    for c in clips_config:
        out_file = os.path.join(audio_dir, f"{c['id']}.mp3")
        c['audio_file'] = out_file
        
        if not (os.path.exists(out_file) and os.path.getsize(out_file) > 1000):
            success = False
            for attempt in range(4):
                try:
                    await asyncio.sleep(0.8)
                    comm = edge_tts.Communicate(c['text'], VOICE, rate=c['rate'])
                    await comm.save(out_file)
                    if os.path.exists(out_file) and os.path.getsize(out_file) > 1000:
                        success = True
                        break
                except Exception as e:
                    print(f"    [Retry {attempt+1}/4] {c['id']}: {e}")
                    await asyncio.sleep(2.0 * (attempt + 1))
            if not success:
                raise RuntimeError(f"Failed speech for {c['id']}")
                
        dur = get_duration(out_file)
        c['target_dur'] = dur
        raw_dur = c['raw_end'] - c['raw_start']
        speed = raw_dur / dur
        print(f"  {c['id']}: raw={raw_dur:.1f}s -> target={dur:.2f}s (speed={speed:.2f}x)")

def render_and_concat():
    print(f"\n=== Rendering {len(clips_config)} Fast-Paced Clips ===")
    clip_files = []
    
    for c in clips_config:
        audio_file = c['audio_file']
        target_dur = c['target_dur']
        raw_dur = c['raw_end'] - c['raw_start']
        pts_factor = target_dur / raw_dur
        out_clip = os.path.join(temp_clips_dir, f"{c['id']}.mp4")
        clip_files.append(out_clip)
        
        vf = (
            f"setpts={pts_factor:.6f}*PTS,"
            f"scale=1920:1080:force_original_aspect_ratio=decrease,"
            f"pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,"
            f"fps=30"
        )
        
        cmd = [
            ffmpeg_exe, '-y',
            '-ss', str(c['raw_start']), '-to', str(c['raw_end']),
            '-i', raw_video,
            '-i', audio_file,
            '-vf', vf,
            '-map', '0:v',
            '-map', '1:a',
            '-c:v', 'libx264', '-preset', 'fast', '-crf', '18',
            '-c:a', 'aac', '-b:a', '192k',
            '-t', str(target_dur),
            out_clip
        ]
        
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode != 0:
            print(f"Error rendering {c['id']}:", res.stderr[-500:])
            raise RuntimeError(f"Failed rendering {c['id']}")
        else:
            print(f"  Rendered {c['id']}: {get_duration(out_clip):.2f}s")
            
    # Concatenate all clips
    concat_list_path = os.path.join(temp_clips_dir, 'concat_list.txt')
    with open(concat_list_path, 'w', encoding='utf-8') as f:
        for cf in clip_files:
            abs_p = os.path.abspath(cf).replace('\\', '/')
            f.write(f"file '{abs_p}'\n")
            
    print(f"\nConcatenating {len(clip_files)} clips into final output...")
    cmd_concat = [
        ffmpeg_exe, '-y',
        '-f', 'concat', '-safe', '0',
        '-i', concat_list_path,
        '-c', 'copy',
        final_output
    ]
    res_concat = subprocess.run(cmd_concat, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res_concat.returncode != 0:
        print("Concatenation failed:", res_concat.stderr[-500:])
        raise RuntimeError("Concatenation failed")
        
    final_dur = get_duration(final_output)
    print(f"\nSUCCESS! High-energy fast-paced narrated video created at:")
    print(f"   {final_output}")
    print(f"   Duration: {final_dur:.2f} seconds ({int(final_dur//60)}m {int(final_dur%60)}s)")

async def main():
    await generate_speech()
    render_and_concat()

if __name__ == '__main__':
    asyncio.run(main())
