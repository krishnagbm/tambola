import subprocess
import os

ffmpeg_exe = r'C:\Users\krish\AppData\Local\Programs\Python\Python312\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe'
input_video = r'C:\Users\krish\Videos\Uploaded\1080p_Converted\Guest_joined_show_ticket_narrated.mp4'
patch_png = r'C:\dev\Tambola\video_assets\room_capacity_patch_1080p.png'
output_video = r'C:\Users\krish\Videos\Player_Ticket_View_Interactive_3x9_Clean_1080p.mp4'

cmd = [
    ffmpeg_exe, '-y',
    '-i', input_video,
    '-i', patch_png,
    '-filter_complex', "[0:v][1:v]overlay=0:0:enable='between(t,29.2,38.2)'[v]",
    '-map', '[v]',
    '-map', '0:a',
    '-c:v', 'libx264',
    '-preset', 'slow',
    '-crf', '18',
    '-c:a', 'copy',
    output_video
]

print("Rendering clean 1080p video with 'Funded Seat' mask...")
res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
if res.returncode != 0:
    print("Error:", res.stderr[-500:])
else:
    size = os.path.getsize(output_video)
    print(f"Successfully rendered: {output_video} ({size} bytes / {size / (1024*1024):.2f} MB)")
