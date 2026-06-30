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

def convert_svg_to_raster(input_path, output_path, target_format, quality=100):
    """Convert SVG input to raster formats using cairosvg"""
    try:
        import cairosvg
        target_fm = target_format.lower()
        if target_fm in ['jpg', 'jpeg']:
            # cairosvg -> PNG bytes -> PIL -> JPEG
            import io
            png_bytes = cairosvg.svg2png(url=input_path, scale=2.0)
            img = Image.open(io.BytesIO(png_bytes)).convert('RGB')
            img.save(output_path, format='JPEG', quality=quality, optimize=True,
                     subsampling=0 if quality == 100 else 2)
        elif target_fm == 'png':
            cairosvg.svg2png(url=input_path, write_to=output_path, scale=2.0)
        elif target_fm == 'pdf':
            cairosvg.svg2pdf(url=input_path, write_to=output_path)
        elif target_fm == 'webp':
            import io
            png_bytes = cairosvg.svg2png(url=input_path, scale=2.0)
            img = Image.open(io.BytesIO(png_bytes)).convert('RGBA')
            webp_kwargs = {'quality': quality, 'method': 4}
            if quality == 100:
                webp_kwargs['lossless'] = True
            img.save(output_path, format='WEBP', **webp_kwargs)
        elif target_fm == 'heif':
            import io
            png_bytes = cairosvg.svg2png(url=input_path, scale=2.0)
            img = Image.open(io.BytesIO(png_bytes)).convert('RGB')
            img.save(output_path, format='HEIF', quality=quality)
        else:
            return False, f"Cannot convert SVG to {target_format}"
        return True, "Success"
    except ImportError:
        return False, "cairosvg not installed. Run: pip3 install cairosvg"
    except Exception as e:
        return False, str(e)

def convert_raster_to_svg(input_path, output_path, quality=100):
    """Convert raster image to SVG using vtracer (vector tracing)"""
    try:
        import vtracer
        import io

        # Load and pre-process the image
        img = Image.open(input_path)

        # For compression mode, downscale slightly to speed up tracing
        if quality < 100:
            img.thumbnail((800, 800), Image.Resampling.LANCZOS)
        else:
            img.thumbnail((1600, 1600), Image.Resampling.LANCZOS)

        # vtracer works with PNG bytes
        buf = io.BytesIO()
        img = img.convert('RGBA')
        img.save(buf, format='PNG')
        png_bytes = buf.getvalue()

        # Use vtracer to convert to SVG
        svg_str = vtracer.convert_raw_image_to_svg(
            png_bytes,
            img_format='png',
            colormode='color',         # 'color' or 'binary'
            hierarchical='stacked',    # 'stacked' or 'cutout'
            mode='spline',             # 'spline', 'polygon', or 'none'
            filter_speckle=4,          # larger = fewer small artifacts
            color_precision=6,         # number of significant bits (1-8)
            layer_difference=16,       # color difference between layers
            corner_threshold=60,       # angle for corner detection
            length_threshold=4.0,      # minimum path segment length
            max_iterations=10,         # curve fitting iterations
            splice_threshold=45,       # angle to splice curve
            path_precision=8           # SVG path decimal places
        )

        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(svg_str)

        return True, "Success"
    except ImportError:
        return False, "vtracer not installed. Run: pip3 install vtracer"
    except Exception as e:
        return False, str(e)

def convert_image(input_path, output_path, target_format, quality=100):
    """Converting images to specified format with quality control"""
    try:
        input_ext = Path(input_path).suffix.lower()
        target_fm = target_format.lower()
        if target_fm == 'jpg':
            target_fm = 'jpeg'

        # --- SVG INPUT ---
        if input_ext == '.svg':
            return convert_svg_to_raster(input_path, output_path, target_fm, quality)

        # --- SVG OUTPUT ---
        if target_fm == 'svg':
            if not input_ext in ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif', '.hif', '.bmp', '.tif', '.tiff']:
                return False, "Input format not supported for SVG conversion"
            return convert_raster_to_svg(input_path, output_path, quality)

        # --- Standard raster conversion ---
        img = Image.open(input_path)

        if quality < 100:
            img.thumbnail((1280, 1280), Image.Resampling.LANCZOS)

        # Preserve metadata
        exif_data = img.info.get('exif', None)
        icc_profile = img.info.get('icc_profile', None)

        save_kwargs = {}
        if exif_data and target_fm in ['jpeg', 'png', 'heif']:
            save_kwargs['exif'] = exif_data
        if icc_profile:
            save_kwargs['icc_profile'] = icc_profile

        if not input_ext in ['.heic', '.heif', '.hif', '.jpg', '.jpeg', '.png', '.webp', '.bmp', '.tif', '.tiff']:
            return False, "Input file format not supported"

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
        elif target_fm in ['heif', 'hif']:
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

def _render_pdf_to_folder(pdf_path, output_folder, target_fm, ext_map, quality, progress_offset=0, progress_total=1):
    """Render all pages of a single PDF into *output_folder*.
    progress_offset / progress_total are used to calculate global progress
    when processing multiple PDFs.
    Returns number of successfully converted pages.
    """
    import fitz  # PyMuPDF for PDF rendering
    pdf_name = Path(pdf_path).stem

    send_to_swift("status", {"message": f"Opening PDF: {os.path.basename(pdf_path)}..."})

    try:
        doc = fitz.open(pdf_path)
    except Exception as e:
        send_to_swift("status", {"message": f"Failed to open PDF {os.path.basename(pdf_path)}: {str(e)}"})
        return 0

    total_pages = len(doc)
    if total_pages == 0:
        send_to_swift("status", {"message": f"PDF {os.path.basename(pdf_path)} has no pages, skipping."})
        doc.close()
        return 0

    send_to_swift("status", {"message": f"Extracting {total_pages} pages from {os.path.basename(pdf_path)}..."})

    dpi = 300
    zoom = dpi / 72.0
    matrix = fitz.Matrix(zoom, zoom)

    converted_count = 0
    for page_num in range(total_pages):
        global_progress = progress_offset + (page_num / total_pages) / progress_total
        send_to_swift("progress", {
            "percent": int(global_progress * 100),
            "current_file": f"{os.path.basename(pdf_path)} — Page {page_num + 1}/{total_pages}"
        })

        try:
            page = doc.load_page(page_num)
            pix = page.get_pixmap(matrix=matrix, alpha=False)

            page_filename = f"{pdf_name}_page_{page_num + 1:03d}{ext_map[target_fm]}"
            page_path = os.path.join(output_folder, page_filename)

            if target_fm in ['jpg', 'jpeg']:
                img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
                img.save(page_path, format='JPEG', quality=quality, optimize=True)
            elif target_fm == 'png':
                pix.save(page_path)
            elif target_fm == 'webp':
                img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
                webp_kwargs = {'quality': quality, 'method': 4}
                if quality == 100:
                    webp_kwargs['lossless'] = True
                img.save(page_path, format='WEBP', **webp_kwargs)

            converted_count += 1
        except Exception as e:
            send_to_swift("status", {"message": f"Failed page {page_num + 1}: {str(e)}"})

    doc.close()
    return converted_count


def process_pdf_to_images(pdf_files, target_format, quality=100):
    """Convert pages of one or more PDF files into images.
    *pdf_files* can be a single path string or a list of paths.
    """
    if isinstance(pdf_files, str):
        pdf_files = [pdf_files]

    ext_map = {
        'jpeg': '.jpg',
        'jpg': '.jpg',
        'png': '.png',
        'webp': '.webp',
    }

    target_fm = target_format.lower()
    if target_fm not in ext_map:
        send_to_swift("error", {"message": f"Format {target_format} not supported for PDF extraction. Use PNG, JPG, or WEBP."})
        return

    # Filter out files that don't exist
    valid_files = [f for f in pdf_files if os.path.exists(f)]
    if not valid_files:
        send_to_swift("error", {"message": "No valid PDF files found."})
        return

    timestamp = int(time.time())
    total_files = len(valid_files)
    total_converted = 0
    output_folders = []

    send_to_swift("status", {"message": f"Processing {total_files} PDF file(s)..."})

    for file_idx, pdf_path in enumerate(valid_files):
        pdf_name = Path(pdf_path).stem

        if total_files == 1:
            output_folder = os.path.join(CONVERTED_FOLDER, f"{pdf_name}_Pages")
        else:
            output_folder = os.path.join(CONVERTED_FOLDER, f"{pdf_name}_Pages_{timestamp}")

        # Avoid collision
        if os.path.exists(output_folder):
            output_folder = os.path.join(CONVERTED_FOLDER, f"{pdf_name}_Pages_{timestamp}_{file_idx}")

        os.makedirs(output_folder, exist_ok=True)

        progress_offset = file_idx / total_files
        count = _render_pdf_to_folder(
            pdf_path, output_folder, target_fm, ext_map, quality,
            progress_offset=progress_offset,
            progress_total=total_files
        )
        total_converted += count
        if count > 0:
            output_folders.append(output_folder)

    if total_converted == 0:
        send_to_swift("error", {"message": "Failed to extract any pages from PDF(s)."})
        return

    # Report success
    if len(output_folders) == 1:
        send_to_swift("success", {
            "filepath": output_folders[0],
            "message": f"{total_converted} pages extracted to folder!"
        })
    else:
        send_to_swift("success", {
            "filepath": CONVERTED_FOLDER,
            "message": f"{total_converted} pages extracted from {len(output_folders)} PDFs!"
        })


def process_batch(files, target_format, quality):
    ext_map = {
        'jpeg': '.jpg',
        'jpg': '.jpg',
        'png': '.png',
        'pdf': '.pdf',
        'heif': '.heif',
        'hif': '.hif',
        'webp': '.webp',
        'svg': '.svg',
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
    parser.add_argument('--format', choices=['jpeg', 'jpg', 'png', 'pdf', 'heif', 'hif', 'webp', 'svg'], default='jpg', help="Target format")
    parser.add_argument('--quality', type=int, default=100, help="Image quality (1-100)")
    parser.add_argument('--mode', choices=['convert', 'pdf2img'], default='convert', help="Operation mode")

    args = parser.parse_args()

    try:
        if args.mode == 'pdf2img':
            process_pdf_to_images(args.files, args.format, args.quality)
        else:
            process_batch(args.files, args.format, args.quality)
    except Exception as e:
        send_to_swift("error", {"message": f"Critical Error: {str(e)}", "traceback": traceback.format_exc()})
