import asyncio
import os
import subprocess

ffmpeg_exe = r'C:\Users\krish\AppData\Local\Programs\Python\Python312\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe'
raw_video = r'C:\Users\krish\Videos\DabHousie Create Trivia Game.mp4'
final_output = r'C:\Users\krish\Videos\DabHousie_Create_Trivia_Game_Narrated.mp4'
audio_dir = r'C:\dev\Tambola\narration_audio\create_trivia'

os.makedirs(audio_dir, exist_ok=True)

VOICE = "en-US-AndrewNeural"

segments = [
    {
        'id': 'seg01_host_intro',
        'start_sec': 1.5,
        'rate': '+0%',
        'text': "Welcome to DabHousie! In this host guide, we will set up a live Tambola party featuring our exclusive Post-Game Recall Trivia. From the organizer dashboard, tap Host Game to launch the event creator."
    },
    {
        'id': 'seg02_capacity_selection',
        'start_sec': 15.5,
        'rate': '+0%',
        'text': "First, choose your expected group size. DabHousie supports everything from family get-togethers to large corporate events. While free Family Packs host up to 5 players, selecting a Small Party of 6 or more automatically unlocks our advanced Cognitive Recall Trivia features."
    },
    {
        'id': 'seg03_trivia_unlock',
        'start_sec': 33.0,
        'rate': '+0%',
        'text': "Notice the DabHousie Recall Trivia card. For 6 or more players, the platform automatically activates post-game cognitive recall. Tapping Learn More reveals the mechanics: testing player memory, observation, and focus right after the final Full House is claimed."
    },
    {
        'id': 'seg04_trivia_pacing_config',
        'start_sec': 52.0,
        'rate': '+0%',
        'text': "Once unlocked, you can configure your trivia experience. Choose your transition pacing—from a seamless 15-second autonomous countdown to a 30-second break or host manual start. Questions are compiled dynamically across winner recall, milestone numbers, room stats, and game duration!"
    },
    {
        'id': 'seg05_scoring_rewards',
        'start_sec': 72.0,
        'rate': '+0%',
        'text': "DabHousie uses a high-speed scoring engine: 500 base points plus up to 500 speed bonus points for rapid answers. You can also attach custom sponsor gifts or company vouchers for the crowned Trivia Champion on the official podium!"
    },
    {
        'id': 'seg06_create_invite',
        'start_sec': 87.0,
        'rate': '+3%',
        'text': "Name your event, verify your prize patterns, and tap Create Game. Your unique 6-character room code is instantly generated, ready to copy and share."
    },
    {
        'id': 'seg07_lobby_launch',
        'start_sec': 98.0,
        'rate': '+3%',
        'text': "Open your Organizer Lobby to track guest check-ins, cast the game to a TV or projector, and start when ready. That is DabHousie!"
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
    print(f"=== Generating {len(segments)} Studio Narration Segments with {VOICE} ===")
    for s in segments:
        out_file = os.path.join(audio_dir, f"{s['id']}.mp3")
        s['file'] = out_file
        
        if not (os.path.exists(out_file) and os.path.getsize(out_file) > 1000):
            success = False
            for attempt in range(4):
                try:
                    await asyncio.sleep(0.8)
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
    
    inputs = ['-i', raw_video]
    filter_parts = []
    
    for i, s in enumerate(segments):
        inputs.extend(['-i', s['file']])
        delay_ms = int(s['start_sec'] * 1000)
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
        final_output
    ]
    
    print("\nMixing narration onto video timeline with FFmpeg...")
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print("FFmpeg error:", res.stderr[-1000:])
        raise RuntimeError("FFmpeg mixing failed")
        
    out_dur = get_duration(final_output)
    print(f"\nSUCCESS! Narrated host video created at:")
    print(f"   {final_output}")
    print(f"   Duration: {out_dur:.2f}s ({int(out_dur//60)}m {int(out_dur%60)}s)")

async def main():
    await generate_speech()
    assemble_narrated_video()

if __name__ == '__main__':
    asyncio.run(main())
