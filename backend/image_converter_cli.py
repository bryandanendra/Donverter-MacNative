import os
import sys
import json
import time
from pathlib import Path
import argparse
import traceback
from PIL import Image
from pillow_heif import register_heif_opener
import zipfile

# Register HEIF opener to support HEIC
try:
    register_heif_opener()
except Exception as e:
    pass

CONVERTED_FOLDER = os.path.expanduser('~/Downloads')
os.makedirs(CONVERTED_FOLDER, exist_ok=True)

def send_to_swift(message_type, data):
    """Mencetak JSON ke stdout agar bisa dibaca oleh aplikasi Swift secara live"""
    message = {"type": message_type}
    message.update(data)
    print(json.dumps(message), flush=True)

def convert_image(input_path, output_path, target_format, quality=100):
    """Converting images to specified format (HEIC/HEIF/JPG/PNG to JPG/PNG/PDF/HEIF) with quality control"""
    try:
        img = Image.open(input_path)
        
        if quality < 100:
            # Compression mode: resize to max 1280px to guarantee file size reduction
            img.thumbnail((1280, 1280), Image.Resampling.LANCZOS)
        
        # Preserve metadata
        exif_data = img.info.get('exif', None)
        icc_profile = img.info.get('icc_profile', None)
        
        save_kwargs = {}
        if exif_data and target_format.lower() in ['jpeg', 'png', 'heif']:
            save_kwargs['exif'] = exif_data
        if icc_profile:
            save_kwargs['icc_profile'] = icc_profile
        
        if not input_path.lower().endswith(('.heic', '.heif', '.jpg', '.jpeg', '.png', '.webp')):
            return False, "Input file format not supported"
        
        target_fm = 'jpeg' if target_format.lower() == 'jpg' else target_format.lower()
        
        if target_fm == 'pdf':
            if img.mode != 'RGB':
                img = img.convert('RGB')
            img.save(output_path, format='PDF', resolution=100.0, **save_kwargs)
        elif target_fm == 'jpeg':
            if img.mode != 'RGB':
                img = img.convert('RGB')
            jpeg_kwargs = {
                'quality': quality,
                'optimize': True,
                **save_kwargs
            }
            if quality == 100:
                jpeg_kwargs['subsampling'] = 0
            img.save(output_path, format='JPEG', **jpeg_kwargs)
        elif target_fm == 'png':
            png_kwargs = {
                'optimize': True,
                **save_kwargs
            }
            img.save(output_path, format='PNG', **png_kwargs)
        elif target_fm == 'heif':
            if img.mode != 'RGB':
                img = img.convert('RGB')
            heif_kwargs = {
                'quality': quality,
                **save_kwargs
            }
            img.save(output_path, format='HEIF', **heif_kwargs)
        elif target_fm == 'webp':
            webp_kwargs = {
                'quality': quality,
                'method': 4,
                **save_kwargs
            }
            if quality == 100:
                webp_kwargs['lossless'] = True
            img.save(output_path, format='WEBP', **webp_kwargs)
        else:
            if img.mode != 'RGB' and target_fm != 'png':
                img = img.convert('RGB')
            img.save(output_path, format=target_fm, **save_kwargs)
        
        return True, "Success"
    except Exception as e:
        return False, str(e)

def process_batch(files, target_format, quality):
    ext_map = {
        'jpeg': '.jpg',
        'jpg': '.jpg',
        'png': '.png',
        'pdf': '.pdf',
        'heif': '.heif',
        'webp': '.webp'
    }
    
    if target_format not in ext_map:
        send_to_swift("error", {"message": f"Format {target_format} not supported"})
        return
        
    send_to_swift("status", {"message": f"Starting conversion of {len(files)} files to {target_format.upper()}..."})
    
    timestamp = int(time.time())
    converted_files = []
    
    total = len(files)
    for i, file_path in enumerate(files):
        if not os.path.exists(file_path):
            continue
            
        send_to_swift("progress", {
            "percent": int((i / total) * 100),
            "current_file": os.path.basename(file_path)
        })
            
        base_filename = Path(file_path).stem
        output_filename = f"{base_filename}_{timestamp}_{i}{ext_map[target_format]}"
        output_path = os.path.join(CONVERTED_FOLDER, output_filename)
        
        # Determine actual absolute path, if it has space spaces it handles it normally
        success, error_msg = convert_image(file_path, output_path, target_format, quality)
        
        if success:
            converted_files.append({
                'path': output_path,
                'clean_name': f"{base_filename}{ext_map[target_format]}"
            })
        else:
            send_to_swift("status", {"message": f"Failed converting {base_filename}: {error_msg}"})
    
    if len(converted_files) == 0:
        send_to_swift("error", {"message": "Failed to convert any image"})
        return
        
    # If multiple files, ZIP them up for convenience or just leave them in folder
    # For Native, better just return the folder or ZIP it as an option. Since it's a batch,
    # Let's create a ZIP to keep things tidy
    if len(converted_files) > 1:
        zip_filename = f"Converted_{target_format.upper()}_{timestamp}.zip"
        zip_path = os.path.join(CONVERTED_FOLDER, zip_filename)
        
        send_to_swift("status", {"message": "Archiving files into ZIP..."})
        try:
            with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
                used_names = {}
                for cf in converted_files:
                    name = cf['clean_name']
                    if name in used_names:
                        used_names[name] += 1
                        base = Path(name).stem
                        ext = Path(name).suffix
                        name = f"{base}_{used_names[name]}{ext}"
                    else:
                        used_names[name] = 0
                    
                    zf.write(cf['path'], name)
                    # Clean up the individual files
                    try:
                        os.remove(cf['path'])
                    except:
                        pass
                        
            send_to_swift("success", {
                "filepath": zip_path,
                "message": f"{len(converted_files)} images converted and zipped!"
            })
        except Exception as e:
            send_to_swift("error", {"message": f"Failed creating ZIP: {str(e)}"})
    else:
        # Single file
        cf = converted_files[0]
        final_clean_path = os.path.join(CONVERTED_FOLDER, f"{Path(cf['clean_name']).stem}_{timestamp}{Path(cf['clean_name']).suffix}")
        os.rename(cf['path'], final_clean_path)
        
        send_to_swift("success", {
            "filepath": final_clean_path,
            "message": "Conversion successful!"
        })

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Image Converter CLI for macOS Native App")
    parser.add_argument('--files', nargs='+', required=True, help="List of file paths to convert")
    parser.add_argument('--format', choices=['jpeg', 'jpg', 'png', 'pdf', 'heif', 'webp'], default='jpg', help="Target format")
    parser.add_argument('--quality', type=int, default=100, help="Image quality (1-100)")
    
    args = parser.parse_args()
    
    try:
        process_batch(args.files, args.format, args.quality)
    except Exception as e:
        send_to_swift("error", {"message": f"Critical Error: {str(e)}", "traceback": traceback.format_exc()})
