import os
import subprocess

ffmpeg_exe = r'C:\Users\krish\AppData\Local\Programs\Python\Python312\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe'
raw_video = r'C:\Users\krish\Videos\Screen Recording 2026-10-25 185516.mp4'
patch_png = r'C:\dev\Tambola\video_assets\room_capacity_patch.png'
final_output = r'C:\Users\krish\Videos\DabHousie_Gameplay_Part1_Narrated.mp4'

os.makedirs('temp_clips', exist_ok=True)

def get_duration(media_path):
    cmd = [ffmpeg_exe, '-i', media_path]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for line in res.stderr.splitlines():
        if 'Duration:' in line:
            parts = line.split('Duration:')[1].split(',')[0].strip().split(':')
            return float(parts[0])*3600 + float(parts[1])*60 + float(parts[2])
    return 0.0

clips = [
    {
        'id': 'clip1_join',
        'raw_start': 2.0,
        'raw_end': 24.5,
        'audio': 'narration_audio/seg1_join.mp3',
        'has_patch': True,
        'patch_start': 17.2,
        'patch_end': 22.5
    },
    {
        'id': 'clip2_lobby',
        'raw_start': 24.5,
        'raw_end': 32.5,
        'audio': 'narration_audio/seg2_lobby.mp3',
        'has_patch': False
    },
    {
        'id': 'clip3_gameplay',
        'raw_start': 32.5,
        'raw_end': 72.0,
        'audio': 'narration_audio/seg3_gameplay.mp3',
        'has_patch': False
    },
    {
        'id': 'clip4_ff1',
        'raw_start': 72.0,
        'raw_end': 116.0,
        'audio': 'narration_audio/seg4_fastforward1.mp3',
        'has_patch': False
    },
    {
        'id': 'clip5_pattern_mismatch',
        'raw_start': 116.0,
        'raw_end': 127.0,
        'audio': 'narration_audio/seg5_pattern_mismatch.mp3',
        'has_patch': False
    },
    {
        'id': 'clip6_ff2',
        'raw_start': 127.0,
        'raw_end': 242.0,
        'audio': 'narration_audio/seg6_fastforward2.mp3',
        'has_patch': False
    },
    {
        'id': 'clip7_bogey_and_unmark',
        'raw_start': 242.0,
        'raw_end': 258.0,
        'audio': 'narration_audio/seg7_bogey_and_unmark.mp3',
        'has_patch': False
    },
    {
        'id': 'clip8_ff3',
        'raw_start': 258.0,
        'raw_end': 282.0,
        'audio': 'narration_audio/seg8_pre_win.mp3',
        'has_patch': False
    },
    {
        'id': 'clip9_topline_win',
        'raw_start': 282.0,
        'raw_end': 304.0,
        'audio': 'narration_audio/seg9_topline_win.mp3',
        'has_patch': False
    },
    {
        'id': 'clip10_race_fullhouse',
        'raw_start': 304.0,
        'raw_end': 518.0,
        'audio': 'narration_audio/seg10_race_fullhouse.mp3',
        'has_patch': False
    },
    {
        'id': 'clip11_rewards',
        'raw_start': 518.0,
        'raw_end': 538.5,
        'audio': 'narration_audio/seg11_rewards.mp3',
        'has_patch': False
    }
]

print('=== Processing 11 Video Clips with Voice & Feature Highlights ===')
clip_files = []

for c in clips:
    audio_file = c['audio']
    target_dur = get_duration(audio_file)
    raw_dur = c['raw_end'] - c['raw_start']
    speed_factor = raw_dur / target_dur
    pts_factor = target_dur / raw_dur
    out_clip = os.path.join('temp_clips', f"{c['id']}.mp4")
    clip_files.append(out_clip)

    print(f"\nProcessing {c['id']}: raw={raw_dur:.1f}s -> target={target_dur:.2f}s (speed={speed_factor:.2f}x)")

    if c['has_patch']:
        vf = (
            f"[0:v]overlay=x=0:y=0:enable='between(t,{c['patch_start']},{c['patch_end']})'[v1];"
            f"[v1]setpts={pts_factor:.6f}*PTS,scale=1920:1080:force_original_aspect_ratio=decrease,"
            f"pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,fps=30[vout]"
        )
        cmd = [
            ffmpeg_exe, '-y',
            '-ss', str(c['raw_start']), '-to', str(c['raw_end']),
            '-i', raw_video,
            '-i', patch_png,
            '-i', audio_file,
            '-filter_complex', vf,
            '-map', '[vout]',
            '-map', '2:a',
            '-c:v', 'libx264', '-preset', 'fast', '-crf', '19',
            '-c:a', 'aac', '-b:a', '192k',
            '-t', str(target_dur),
            out_clip
        ]
    else:
        vf = (
            f"setpts={pts_factor:.6f}*PTS,scale=1920:1080:force_original_aspect_ratio=decrease,"
            f"pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,fps=30"
        )
        cmd = [
            ffmpeg_exe, '-y',
            '-ss', str(c['raw_start']), '-to', str(c['raw_end']),
            '-i', raw_video,
            '-i', audio_file,
            '-vf', vf,
            '-map', '0:v',
            '-map', '1:a',
            '-c:v', 'libx264', '-preset', 'fast', '-crf', '19',
            '-c:a', 'aac', '-b:a', '192k',
            '-t', str(target_dur),
            out_clip
        ]

    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print(f"Error processing {c['id']}:", res.stderr[-500:])
        raise RuntimeError(f"Failed to process {c['id']}")
    else:
        print(f"Rendered {out_clip} successfully ({get_duration(out_clip):.2f}s).")

concat_list_path = os.path.join('temp_clips', 'concat_list.txt')
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
    print("Error during concatenation:", res_concat.stderr[-500:])
    raise RuntimeError("Concatenation failed")

total_dur = get_duration(final_output)
print(f"\nSUCCESS: Final narrated video created at:")
print(f"   {final_output}")
print(f"   Total Duration: {total_dur:.2f} seconds ({int(total_dur//60)}m {int(total_dur%60)}s)")
