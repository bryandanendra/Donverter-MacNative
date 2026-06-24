import os
import sys
import json
import time
import re
import subprocess
import argparse
from yt_dlp import YoutubeDL
import traceback

DOWNLOAD_FOLDER = os.path.expanduser('~/Downloads')
os.makedirs(DOWNLOAD_FOLDER, exist_ok=True)

def get_ffmpeg_path():
    if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, 'ffmpeg')
    return os.path.join(os.path.dirname(__file__), 'bin', 'ffmpeg')

def get_ffprobe_path():
    if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, 'ffprobe')
    return os.path.join(os.path.dirname(__file__), 'bin', 'ffprobe')

def send_to_swift(message_type, data):
    """Mencetak JSON ke stdout agar bisa dibaca oleh aplikasi Swift secara live"""
    message = {"type": message_type}
    message.update(data)
    # Gunakan flush=True agar Swift langsung menerimanya seketika
    print(json.dumps(message), flush=True)

def force_reencode_to_h264(filepath):
    """Sama seperti sebelumnya: Memaksa video menjadi QuickTime compatible"""
    if not os.path.exists(filepath) or not filepath.lower().endswith('.mp4'):
        return filepath
    
    send_to_swift("status", {"message": "Verifying compatibility..."})
    try:
        probe_result = subprocess.run(
            [get_ffprobe_path(), '-v', 'error', '-select_streams', 'v:0',
             '-show_entries', 'stream=codec_name', '-of', 'csv=p=0', filepath],
            capture_output=True, text=True, timeout=10
        )
        current_codec = probe_result.stdout.strip()
        if current_codec == 'h264':
            send_to_swift("status", {"message": "Format verified."})
            return filepath
        else:
            send_to_swift("status", {"message": f"Optimizing format ({current_codec.upper()} to H.264)..."})
    except Exception as e:
        send_to_swift("status", {"message": "Re-encoding to ensure compatibility..."})
    
    temp_output = filepath.replace('.mp4', '_h264_temp.mp4')
    try:
        result = subprocess.run([
            get_ffmpeg_path(), '-i', filepath,
            '-c:v', 'h264_videotoolbox', '-q:v', '50',
            '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart',
            '-pix_fmt', 'yuv420p', '-y', temp_output
        ], capture_output=True, text=True, timeout=300)
        
        if result.returncode == 0 and os.path.exists(temp_output):
            os.remove(filepath)
            os.rename(temp_output, filepath)
            send_to_swift("status", {"message": "Optimization complete."})
        else:
            if os.path.exists(temp_output):
                os.remove(temp_output)
            send_to_swift("status", {"message": "Optimization bypassed."})
    except Exception as e:
        if os.path.exists(temp_output):
            os.remove(temp_output)
    
    return filepath

def get_progress_hook():
    def progress_hook(d):
        if d['status'] == 'downloading':
            ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
            percent = ansi_escape.sub('', d.get('_percent_str', '0%')).replace('%', '').strip()
            speed = ansi_escape.sub('', d.get('_speed_str', 'N/A')).strip()
            eta = ansi_escape.sub('', d.get('_eta_str', 'N/A')).strip()
            
            # Kirim progress live ke Swift!
            send_to_swift("progress", {
                "percent": percent,
                "speed": speed,
                "eta": eta
            })
        elif d['status'] == 'finished':
            send_to_swift("status", {"message": "Download finished, processing video..."})
    return progress_hook

def download_video(url, platform, format_type='mp4', resolution='best'):
    send_to_swift("status", {"message": f"Initializing download for {platform}..."})
    
    ydl_opts = {
        'progress_hooks': [get_progress_hook()],
        'outtmpl': f'{DOWNLOAD_FOLDER}/%(title)s.%(ext)s',
        'noplaylist': True,
        'quiet': True,
        'no_warnings': True,
        'ffmpeg_location': get_ffmpeg_path(),
    }
    
    if format_type == 'mp3':
        ydl_opts['format'] = 'bestaudio/best'
        ydl_opts['postprocessors'] = [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': 'mp3',
            'preferredquality': '320',
        }]
    else:
        if platform == 'youtube':
            if resolution and resolution != 'best':
                # Batasi tinggi video maksimal sesuai resolusi yang diminta.
                # Kita tidak memfilter codec di sini agar yt-dlp memilih resolusi tertinggi yang tersedia.
                ydl_opts['format'] = f'bestvideo[height<={resolution}]+bestaudio/best'
            else:
                ydl_opts['format'] = 'bestvideo+bestaudio/best'
            
            # Gunakan format_sort untuk memprioritaskan resolusi tertinggi terlebih dahulu,
            # kemudian memprioritaskan AVC/H.264 di antara format-format dengan resolusi yang sama.
            ydl_opts['format_sort'] = ['res', 'vcodec:avc']
            ydl_opts['merge_output_format'] = 'mp4'
        else: # Instagram & TikTok
            ydl_opts['format'] = 'bestvideo[vcodec^=avc]+bestaudio[acodec^=mp4a]/bestvideo+bestaudio/best'
            ydl_opts['merge_output_format'] = 'mp4'

    files_before = set([os.path.join(DOWNLOAD_FOLDER, f) for f in os.listdir(DOWNLOAD_FOLDER)])
    
    try:
        with YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            
            # Cari file hasil download
            actual_file = None
            for f in os.listdir(DOWNLOAD_FOLDER):
                fpath = os.path.join(DOWNLOAD_FOLDER, f)
                if fpath not in files_before and os.path.isfile(fpath):
                    actual_file = fpath
                    break
            
            if not actual_file:
                raise Exception("Cannot find downloaded file.")
                
            # Deteksi jika user minta MP4 tapi yang didownload MP3 (biasanya karena TikTok Photo Slideshow)
            is_slideshow = platform == 'tiktok' and format_type == 'mp4' and actual_file.lower().endswith('.mp3')
            
            # Paksa H.264 untuk semua platform (QuickTime/macOS compatible)
            # YouTube sekarang banyak pakai VP9/AV1 — perlu di-encode ulang
            if format_type == 'mp4' and not is_slideshow:
                force_reencode_to_h264(actual_file)
                
            success_msg = "Note: Photo Slideshow downloaded as Audio (MP3) only." if is_slideshow else "Download Complete!"
            send_to_swift("success", {
                "message": success_msg,
                "filepath": os.path.abspath(actual_file),
                "filename": os.path.basename(actual_file)
            })

    except Exception as e:
        send_to_swift("error", {"message": str(e)})

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="CLI Video Downloader for macOS Native App")
    parser.add_argument('--url', required=True, help="URL of the video to download")
    parser.add_argument('--platform', required=True, choices=['youtube', 'instagram', 'tiktok'], help="Target platform")
    parser.add_argument('--format', choices=['mp4', 'mp3'], default='mp4', help="Output format")
    parser.add_argument('--resolution', choices=['360', '480', '720', '1080', '1440', '2160', 'best'], default='best', help="Video resolution")
    
    args = parser.parse_args()
    
    # Supaya error tidak merusak format JSON si Swift
    try:
        download_video(args.url, args.platform, args.format, resolution=args.resolution)
    except Exception as e:
        send_to_swift("error", {"message": f"Critical Error: {str(e)}", "traceback": traceback.format_exc()})
