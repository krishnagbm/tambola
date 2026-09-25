# backend/functions/email_ses.py
# DabHousie — Amazon SES Email Dispatcher
# Sends automated, branded purchase receipts and notification emails

import os
import urllib.request
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.image import MIMEImage
from typing import Optional, List, Dict, Any, Tuple

try:
    import boto3
    from botocore.exceptions import ClientError
except ImportError:
    boto3 = None
    ClientError = Exception

SES_REGION = os.getenv("AWS_SES_REGION", os.getenv("AWS_REGION", "us-east-2"))
FROM_EMAIL = os.getenv("SES_FROM_EMAIL", os.getenv("SUPPORT_EMAIL", "receipts@dabhousie.com"))
PARTNERSHIPS_EMAIL = os.getenv("PARTNERSHIPS_EMAIL", "partnerships@dabhousie.com")
BASE_URL = os.getenv("BASE_URL", "https://www.dabhousie.com")
AUDIT_EMAIL = os.getenv("AUDIT_EMAIL", "contact@dabhousie.com")


def send_purchase_email(
    to_email: str,
    pack: str,
    credits: int,
    new_balance: int,
    amount_paid: float,
    currency: str = "USD",
    session_id: Optional[str] = None,
) -> bool:
    """
    Sends a rich HTML purchase confirmation receipt to the customer via AWS SES.
    """
    if not to_email:
        print("  [ SES ] No recipient email provided. Skipping email dispatch.")
        return False

    pack_display = pack.replace("_", " ").title()
    currency_symbol = "$" if currency.upper() == "USD" else currency.upper() + " "
    amount_str = f"{currency_symbol}{amount_paid:.2f}"

    subject = f"Receipt: {credits} DabHousie Credits Added to Your Account 🎉"

    html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Your DabHousie Receipt</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background-color: #0d1117;
      color: #e6edf3;
      margin: 0;
      padding: 24px;
    }}
    .container {{
      max-width: 580px;
      margin: 0 auto;
      background: #161b22;
      border: 1px solid #30363d;
      border-radius: 16px;
      overflow: hidden;
      box-shadow: 0 10px 30px rgba(0,0,0,0.5);
    }}
    .header {{
      background: linear-gradient(135deg, #0B3D91 0%, #1e293b 100%);
      padding: 28px 24px;
      text-align: center;
      border-bottom: 2px solid #FFC107;
    }}
    .header img {{
      max-width: 220px;
      height: auto;
      display: block;
      margin: 0 auto 8px;
    }}
    .header p {{
      margin: 4px 0 0 0;
      color: #FFC107;
      font-size: 13.5px;
      font-weight: 600;
      letter-spacing: 0.5px;
    }}
    .content {{
      padding: 32px 24px;
    }}
    .receipt-card {{
      background: #0d1117;
      border: 1px solid #30363d;
      border-radius: 12px;
      padding: 20px;
      margin-bottom: 24px;
    }}
    .receipt-row {{
      display: flex;
      justify-content: space-between;
      padding: 10px 0;
      border-bottom: 1px solid #21262d;
      font-size: 14px;
    }}
    .receipt-row:last-child {{
      border-bottom: none;
      padding-top: 14px;
      font-weight: bold;
      font-size: 16px;
    }}
    .label {{
      color: #8b949e;
    }}
    .value {{
      color: #ffffff;
      text-align: right;
    }}
    .highlight {{
      color: #FFC107;
      font-weight: bold;
    }}
    .balance-badge {{
      background: rgba(46, 204, 113, 0.15);
      border: 1px solid rgba(46, 204, 113, 0.4);
      color: #2ECC71;
      padding: 14px 20px;
      border-radius: 10px;
      text-align: center;
      font-size: 15px;
      font-weight: bold;
      margin-bottom: 24px;
    }}
    .btn {{
      display: block;
      width: 100%;
      box-sizing: border-box;
      background: #0B3D91;
      color: #ffffff !important;
      text-decoration: none;
      text-align: center;
      padding: 16px;
      border-radius: 10px;
      font-weight: bold;
      font-size: 15px;
      margin-top: 16px;
      border: 1px solid #3b82f6;
    }}
    .footer {{
      padding: 20px 24px;
      background: #0d1117;
      text-align: center;
      font-size: 12px;
      color: #8b949e;
      border-top: 1px solid #21262d;
    }}
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <a href="{BASE_URL}" target="_blank" style="text-decoration:none;">
        <img src="{BASE_URL}/dabhousie_horizontal_logo.png" alt="DabHousie" width="220" style="max-width:220px; height:auto; display:block; margin:0 auto 8px; border:0;" />
      </a>
      <p>Multiplayer Tambola, Housie & Bingo</p>
    </div>
    <div class="content">
      <h2 style="margin-top:0; color:#ffffff; font-size:20px;">Thank you for your purchase!</h2>
      <p style="color:#8b949e; font-size:14px; line-height:1.5;">
        Your payment was successfully processed by Stripe. Your credits are active and ready to use immediately for hosting games.
      </p>

      <div class="receipt-card">
        <div class="receipt-row">
          <span class="label">Package</span>
          <span class="value">{pack_display}</span>
        </div>
        <div class="receipt-row">
          <span class="label">Credits Purchased</span>
          <span class="value highlight">+{credits} Credits</span>
        </div>
        <div class="receipt-row">
          <span class="label">Amount Paid</span>
          <span class="value">{amount_str}</span>
        </div>
        <div class="receipt-row">
          <span class="label">Payment Provider</span>
          <span class="value">Stripe (Card)</span>
        </div>
        {f'''<div class="receipt-row">
          <span class="label">Reference ID</span>
          <span class="value" style="font-family:monospace; font-size:11px; color:#8b949e;">{session_id[:24]}...</span>
        </div>''' if session_id else ''}
        <div class="receipt-row">
          <span class="label">Total Paid</span>
          <span class="value highlight">{amount_str}</span>
        </div>
      </div>

      <div class="balance-badge">
        ⭐ Updated Available Balance: <strong>{new_balance} Credits</strong>
      </div>

      <p style="color:#8b949e; font-size:13px;">
        💡 <em>Credits are valid for 1 year from your most recent paid game and are deducted automatically at game start based on confirmed players.</em>
      </p>

      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-top:20px;">
        <tr>
          <td align="center" bgcolor="#0B3D91" style="background-color:#0B3D91; border-radius:10px; border:1px solid #3b82f6; padding:0;">
            <a href="{BASE_URL}/#/wallet" target="_blank" style="background-color:#0B3D91; color:#ffffff !important; display:block; width:100%; box-sizing:border-box; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:15px; font-weight:bold; text-decoration:none; text-align:center; padding:16px 20px; border-radius:10px; line-height:1.2;">
              Go to My DabHousie Wallet &rarr;
            </a>
          </td>
        </tr>
      </table>
    </div>
    <div class="footer">
      DabHousie &bull; <a href="{BASE_URL}" style="color:#38bdf8; text-decoration:none;">www.dabhousie.com</a><br>
      Questions or support? Contact us at <a href="mailto:{FROM_EMAIL}" style="color:#38bdf8;">{FROM_EMAIL}</a>
    </div>
  </div>
</body>
</html>
"""

    text_content = f"""Thank you for your purchase at DabHousie!

Package: {pack_display}
Credits Added: +{credits} Credits
Amount Paid: {amount_str}
New Balance: {new_balance} Credits

Your credits are ready to use immediately.
Visit your wallet: {BASE_URL}/#/wallet

Support: {FROM_EMAIL}
"""

    if boto3 is None:
        print(f"  [ SES (Dev / Log Mode) ] Email simulated to {to_email}: +{credits} credits, balance={new_balance}")
        return True

    try:
        ses_client = boto3.client("ses", region_name=SES_REGION)
        ses_client.send_email(
            Source=f"DabHousie <{FROM_EMAIL}>",
            Destination={"ToAddresses": [to_email]},
            Message={
                "Subject": {"Data": subject, "Charset": "UTF-8"},
                "Body": {
                    "Html": {"Data": html_content, "Charset": "UTF-8"},
                    "Text": {"Data": text_content, "Charset": "UTF-8"},
                },
            },
        )
        print(f"  [ SES ] Purchase receipt successfully sent to {to_email}")
        return True
    except ClientError as e:
        print(f"  [ SES ERROR ] Failed to send receipt email via SES: {e.response['Error']['Message']}")
        return False
    except Exception as e:
        print(f"  [ SES ERROR ] Unexpected email error: {e}")
        return False


def send_private_party_otps_email(
    to_email: str,
    game_name: str,
    invite_code: str,
    otps_list: list,
    scheduled_at: Optional[str] = None,
) -> bool:
    """
    Sends the Private Party join link and list of single-use Seat OTPs to the organizer
    with official DabHousie branding and high-contrast email client styling.
    """
    if not to_email:
        print("  [ SES ] No recipient email provided. Skipping email dispatch.")
        return False

    subject = f"Private Party Passcodes: {game_name} (Code: {invite_code})"
    join_url = f"{BASE_URL}/#/join/{invite_code}"
    dashboard_url = f"{BASE_URL}/#/admin/lobby/{invite_code}"

    otp_table_rows = ""
    otp_rows_text = ""
    for idx, item in enumerate(otps_list, 1):
        seat_num = item.get("seat_number", idx) if isinstance(item, dict) else idx
        otp_code = item.get("otp_code", item) if isinstance(item, dict) else str(item)
        otp_table_rows += f"""
        <tr>
          <td style="background:#161f30; padding:10px 14px; border-radius:8px 0 0 8px; border:1px solid #293548; border-right:none; color:#f8fafc; font-size:14px; font-weight:700;">
            <span style="display:inline-block; width:8px; height:8px; border-radius:50%; background:#22c55e; margin-right:8px; vertical-align:middle;"></span>
            Seat #{seat_num}
          </td>
          <td align="right" style="background:#161f30; padding:10px 14px; border-radius:0 8px 8px 0; border:1px solid #293548; border-left:none;">
            <span style="background:#0284c7; color:#ffffff; font-family:Courier, 'Courier New', monospace; font-size:16px; font-weight:800; letter-spacing:2px; padding:6px 14px; border-radius:6px; display:inline-block;">{otp_code}</span>
          </td>
        </tr>
        """
        otp_rows_text += f"Seat #{seat_num}: Passcode {otp_code}\n"

    html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Private Party Passcodes - {game_name}</title>
</head>
<body style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color:#080c14; color:#e2e8f0; margin:0; padding:20px 10px;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#080c14; margin:0; padding:0;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px; background:#111827; border:1px solid #374151; border-radius:16px; overflow:hidden; box-shadow:0 12px 32px rgba(0,0,0,0.6);">
          <!-- Header with Official Brand Logo -->
          <tr>
            <td style="background:linear-gradient(135deg, #0B3D91 0%, #0f172a 100%); padding:28px 20px; text-align:center; border-bottom:3px solid #f59e0b;">
              <a href="{BASE_URL}" target="_blank" style="text-decoration:none; display:inline-block;">
                <img src="{BASE_URL}/dabhousie_horizontal_logo.png" alt="DabHousie" width="220" style="max-width:220px; height:auto; display:block; margin:0 auto 10px auto; border:0; outline:none;" />
              </a>
              <p style="margin:0 0 12px 0; color:#f59e0b; font-size:12px; font-weight:700; text-transform:uppercase; letter-spacing:1.5px;">Multiplayer Tambola &bull; Housie &bull; Bingo</p>
              <h1 style="margin:0; color:#ffffff; font-size:22px; font-weight:800; letter-spacing:0.3px;">🔒 Private Party Access Passcodes</h1>
              <p style="margin:6px 0 0 0; color:#93c5fd; font-size:15px; font-weight:600;">{game_name}</p>
            </td>
          </tr>

          <!-- Main Content Body -->
          <tr>
            <td style="padding:28px 24px;">
              <!-- Master Join Box -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0b1120; border:1px solid #1e293b; border-radius:12px; margin-bottom:20px;">
                <tr>
                  <td style="padding:16px 18px;">
                    <div style="font-size:12px; font-weight:700; color:#94a3b8; text-transform:uppercase; letter-spacing:0.8px; margin-bottom:6px;">Master Join Link</div>
                    <div style="background:#1e293b; border:1px solid #334155; border-radius:8px; padding:10px 14px; margin-bottom:12px; word-break:break-all;">
                      <a href="{join_url}" target="_blank" style="color:#38bdf8; font-size:14px; font-weight:700; text-decoration:underline;">{join_url}</a>
                    </div>
                    <table width="100%" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="color:#94a3b8; font-size:13px;">
                          Party Code: <span style="background:#f59e0b; color:#000000; font-family:Courier,'Courier New',monospace; font-weight:800; font-size:14px; padding:3px 8px; border-radius:5px;">{invite_code}</span>
                        </td>
                        <td align="right" style="color:#94a3b8; font-size:13px;">
                          Reserved Seats: <strong style="color:#ffffff; font-size:14px;">{len(otps_list)}</strong>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Distribution Instructions (High Contrast) -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0c203a; border:1px solid #1e40af; border-left:4px solid #38bdf8; border-radius:0 10px 10px 0; margin-bottom:24px;">
                <tr>
                  <td style="padding:16px 18px;">
                    <div style="color:#38bdf8; font-size:14px; font-weight:700; margin-bottom:8px;">📌 How to Distribute to Your Team:</div>
                    <p style="margin:0 0 6px 0; color:#e2e8f0; font-size:13.5px; line-height:1.5;"><strong>1.</strong> Share the Master Join Link with your team members.</p>
                    <p style="margin:0 0 6px 0; color:#e2e8f0; font-size:13.5px; line-height:1.5;"><strong>2.</strong> Assign <strong>one unique passcode</strong> below to each invited member.</p>
                    <p style="margin:0; color:#e2e8f0; font-size:13.5px; line-height:1.5;"><strong>3.</strong> Each passcode is single-use and binds securely to that player's device.</p>
                  </td>
                </tr>
              </table>

              <!-- Single-Use Seat Passcodes Header -->
              <div style="font-size:15px; font-weight:700; color:#f8fafc; margin-bottom:12px;">
                🎟️ Single-Use Seat Passcodes ({len(otps_list)} Total):
              </div>

              <!-- Passcodes Table -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:separate; border-spacing:0 8px;">
                {otp_table_rows}
              </table>

              <!-- CTA Button (Bulletproof email button for Outlook, Hotmail, and Gmail) -->
              <table cellpadding="0" cellspacing="0" border="0" align="center" style="margin:26px auto 0 auto;">
                <tr>
                  <td align="center" bgcolor="#f59e0b" style="background-color:#f59e0b; border-radius:8px; border:1px solid #d97706; padding:0;">
                    <a href="{dashboard_url}" target="_blank" style="background-color:#f59e0b; color:#0f172a !important; display:inline-block; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:15px; font-weight:800; text-decoration:none; padding:14px 32px; border-radius:8px; line-height:1.2; letter-spacing:0.3px;">
                      Open Host Dashboard &rarr;
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Footer / Trust Badges -->
          <tr>
            <td style="padding:22px 24px; background:#0b1120; border-top:1px solid #1f2937; text-align:center; font-size:12px; color:#94a3b8; line-height:1.6;">
              <p style="margin:0 0 6px 0; color:#cbd5e1; font-weight:600;">🛡️ <strong>Zero-PII Architecture</strong> &bull; Player emails and phone numbers are never collected or stored.</p>
              <p style="margin:0;">DabHousie &bull; <a href="{BASE_URL}" target="_blank" style="color:#38bdf8; text-decoration:none;">www.dabhousie.com</a> &bull; Support: <a href="mailto:{FROM_EMAIL}" style="color:#38bdf8; text-decoration:none;">{FROM_EMAIL}</a></p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"""

    text_content = f"""Private Party Access Passcodes for {game_name}
Party Code: {invite_code}
Join Link: {join_url}
Total Seats: {len(otps_list)}

How to Distribute:
1. Share the Master Join Link with your team.
2. Give one unique passcode to each member. Once entered, the seat binds to that device.

Passcodes:
{otp_rows_text}
Host Dashboard: {dashboard_url}
Support: {FROM_EMAIL}
"""

    if boto3 is None:
        print(f"  [ SES (Dev / Log Mode) ] Private party OTPs email simulated to {to_email} ({len(otps_list)} seats).")
        return True

    try:
        ses_client = boto3.client("ses", region_name=SES_REGION)
        ses_client.send_email(
            Source=f"DabHousie <{FROM_EMAIL}>",
            Destination={"ToAddresses": [to_email]},
            Message={
                "Subject": {"Data": subject, "Charset": "UTF-8"},
                "Body": {
                    "Html": {"Data": html_content, "Charset": "UTF-8"},
                    "Text": {"Data": text_content, "Charset": "UTF-8"},
                },
            },
        )
        print(f"  [ SES ] Private party OTPs successfully sent to {to_email}")
        return True
    except Exception as e:
        print(f"  [ SES ERROR ] Failed to send private party OTPs email: {e}")
        return False


def _autocrop_png_bytes(png_bytes: bytes) -> bytes:
    """
    Pure-Python (standard library struct + zlib) PNG auto-cropper that trims surrounding
    transparent or near-white border padding from scraped corporate logos (e.g. Logo.dev).
    """
    import struct
    import zlib

    try:
        if not png_bytes or not png_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
            return png_bytes
        pos = 8
        width = height = bit_depth = color_type = interlace = 0
        idat_chunks = []
        while pos + 8 <= len(png_bytes):
            length = struct.unpack(">I", png_bytes[pos : pos + 4])[0]
            ctype = png_bytes[pos + 4 : pos + 8]
            cdata = png_bytes[pos + 8 : pos + 8 + length]
            pos += 12 + length
            if ctype == b"IHDR":
                width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", cdata)
            elif ctype == b"IDAT":
                idat_chunks.append(cdata)
            elif ctype == b"IEND":
                break

        if bit_depth != 8 or color_type not in (2, 6) or interlace != 0 or not idat_chunks:
            return png_bytes

        bpp = 4 if color_type == 6 else 3
        raw = zlib.decompress(b"".join(idat_chunks))
        stride = width * bpp
        rows = []
        prev = bytearray(stride)
        idx = 0
        for _ in range(height):
            f = raw[idx]
            idx += 1
            cur = bytearray(raw[idx : idx + stride])
            idx += stride
            if f == 1:
                for i in range(bpp, stride):
                    cur[i] = (cur[i] + cur[i - bpp]) & 0xFF
            elif f == 2:
                for i in range(stride):
                    cur[i] = (cur[i] + prev[i]) & 0xFF
            elif f == 3:
                for i in range(stride):
                    a = cur[i - bpp] if i >= bpp else 0
                    cur[i] = (cur[i] + ((a + prev[i]) >> 1)) & 0xFF
            elif f == 4:
                for i in range(stride):
                    a = cur[i - bpp] if i >= bpp else 0
                    b = prev[i]
                    c = prev[i - bpp] if i >= bpp else 0
                    p = a + b - c
                    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                    pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                    cur[i] = (cur[i] + pr) & 0xFF
            rows.append(cur)
            prev = cur

        min_x, min_y, max_x, max_y = width, height, -1, -1
        for y in range(height):
            row = rows[y]
            for x in range(width):
                off = x * bpp
                r, g, b = row[off], row[off + 1], row[off + 2]
                a = row[off + 3] if bpp == 4 else 255
                if a < 25:
                    continue
                if r > 242 and g > 242 and b > 242:
                    continue
                if x < min_x:
                    min_x = x
                if x > max_x:
                    max_x = x
                if y < min_y:
                    min_y = y
                if y > max_y:
                    max_y = y

        if max_x < min_x or max_y < min_y:
            return png_bytes

        pad = max(2, int(max(max_x - min_x + 1, max_y - min_y + 1) * 0.06))
        min_x = max(0, min_x - pad)
        min_y = max(0, min_y - pad)
        max_x = min(width - 1, max_x + pad)
        max_y = min(height - 1, max_y + pad)
        nw = max_x - min_x + 1
        nh = max_y - min_y + 1
        if nw >= width * 0.9 and nh >= height * 0.9:
            return png_bytes

        out_raw = bytearray()
        for y in range(min_y, max_y + 1):
            out_raw.append(0)
            out_raw.extend(rows[y][min_x * bpp : (max_x + 1) * bpp])

        def make_chunk(ct: bytes, cd: bytes) -> bytes:
            return struct.pack(">I", len(cd)) + ct + cd + struct.pack(">I", zlib.crc32(ct + cd) & 0xFFFFFFFF)

        ihdr = struct.pack(">IIBBBBB", nw, nh, 8, color_type, 0, 0, 0)
        return (
            b"\x89PNG\r\n\x1a\n"
            + make_chunk(b"IHDR", ihdr)
            + make_chunk(b"IDAT", zlib.compress(bytes(out_raw), 9))
            + make_chunk(b"IEND", b"")
        )
    except Exception as e:
        print(f"  [ SES ] PNG auto-crop skipped: {e}")
        return png_bytes


def _fetch_inline_logos(organization_logo_url: Optional[str] = None) -> Tuple[Optional[bytes], str, Optional[bytes], str]:
    """
    Loads DabHousie and corporate logos for inline MIME CID embedding to prevent image blocking in Outlook/Gmail,
    automatically cropping excess transparent/white padding from corporate logos.
    """
    import re

    dabhousie_logo_bytes = None
    local_logo_path = os.path.join(os.path.dirname(__file__), "assets", "dabhousie_horizontal_logo.png")
    if os.path.exists(local_logo_path):
        try:
            with open(local_logo_path, "rb") as f:
                dabhousie_logo_bytes = f.read()
        except Exception as e:
            print(f"  [ SES ] Could not read local DabHousie logo: {e}")

    if not dabhousie_logo_bytes:
        try:
            req = urllib.request.Request(f"{BASE_URL}/dabhousie_horizontal_logo.png", headers={"User-Agent": "DabHousie-SES"})
            with urllib.request.urlopen(req, timeout=3) as resp:
                dabhousie_logo_bytes = resp.read()
        except Exception:
            pass

    header_logo_src = "cid:logo_dabhousie" if dabhousie_logo_bytes else f"{BASE_URL}/dabhousie_horizontal_logo.png"

    org_logo_bytes = None
    if organization_logo_url:
        fetch_url = organization_logo_url.strip()
        if "img.logo.dev" in fetch_url:
            fetch_url = re.sub(r"size=\d+", "size=256", fetch_url)
        try:
            req = urllib.request.Request(fetch_url, headers={"User-Agent": "Mozilla/5.0 (DabHousie-SES)"})
            with urllib.request.urlopen(req, timeout=4) as resp:
                raw_logo = resp.read()
                org_logo_bytes = _autocrop_png_bytes(raw_logo)
        except Exception as e:
            print(f"  [ SES ] Could not fetch org logo for inline CID: {e}")

    org_logo_src = "cid:logo_org" if org_logo_bytes else (organization_logo_url or "")
    return dabhousie_logo_bytes, header_logo_src, org_logo_bytes, org_logo_src


def _dispatch_ses_mime_or_standard(
    to_email: str,
    subject: str,
    html_content: str,
    text_content: str,
    dabhousie_logo_bytes: Optional[bytes] = None,
    org_logo_bytes: Optional[bytes] = None,
    audit_email: Optional[str] = AUDIT_EMAIL,
    extra_to: Optional[str] = None,
    from_email: Optional[str] = None,
    from_display_name: str = "DabHousie",
) -> bool:
    """
    Dispatches SES email with raw MIME CID inline images, falling back to standard send_email.
    Guarantees that audit_email is copied for immutable compliance.
    """
    sender_address = (from_email or FROM_EMAIL).strip()
    sender_header = f"{from_display_name} <{sender_address}>"

    if boto3 is None:
        print(f"  [ SES (Dev / Log Mode) ] Email simulated from {sender_header} to {to_email} (Cc: {audit_email}): '{subject}'.")
        return True

    try:
        ses_client = boto3.client("ses", region_name=SES_REGION)

        # Collect recipient and CC destinations
        to_recipients = [to_email]
        if extra_to and extra_to.lower() != to_email.lower():
            to_recipients.append(extra_to)

        cc_recipients = []
        if audit_email and audit_email.lower() not in [e.lower() for e in to_recipients]:
            cc_recipients.append(audit_email)

        all_destinations = list(set(to_recipients + cc_recipients))

        # Prefer raw email with inline MIME attachments for Outlook/Gmail rendering
        if dabhousie_logo_bytes or org_logo_bytes:
            try:
                msg_root = MIMEMultipart("related")
                msg_root["Subject"] = subject
                msg_root["From"] = sender_header
                msg_root["Reply-To"] = sender_address
                msg_root["To"] = ", ".join(to_recipients)
                if cc_recipients:
                    msg_root["Cc"] = ", ".join(cc_recipients)

                msg_alt = MIMEMultipart("alternative")
                msg_root.attach(msg_alt)

                msg_alt.attach(MIMEText(text_content, "plain", "utf-8"))
                msg_alt.attach(MIMEText(html_content, "html", "utf-8"))

                if dabhousie_logo_bytes:
                    img_dab = MIMEImage(dabhousie_logo_bytes, "png")
                    img_dab.add_header("Content-ID", "<logo_dabhousie>")
                    img_dab.add_header("Content-Disposition", "inline", filename="dabhousie_logo.png")
                    msg_root.attach(img_dab)

                if org_logo_bytes:
                    img_org = MIMEImage(org_logo_bytes)
                    img_org.add_header("Content-ID", "<logo_org>")
                    img_org.add_header("Content-Disposition", "inline", filename="org_logo.png")
                    msg_root.attach(img_org)

                ses_client.send_raw_email(
                    Source=sender_header,
                    Destinations=all_destinations,
                    RawMessage={"Data": msg_root.as_string()},
                )
                print(f"  [ SES ] Raw MIME email sent from {sender_header} to {to_recipients} (Cc: {cc_recipients}): '{subject}'")
                return True
            except Exception as e_raw:
                print(f"  [ SES WARNING ] Raw MIME dispatch failed, falling back to standard send_email: {e_raw}")

        # Fallback to standard SES send_email
        destination_dict = {"ToAddresses": to_recipients}
        if cc_recipients:
            destination_dict["CcAddresses"] = cc_recipients

        ses_client.send_email(
            Source=sender_header,
            Destination=destination_dict,
            ReplyToAddresses=[sender_address],
            Message={
                "Subject": {"Data": subject, "Charset": "UTF-8"},
                "Body": {
                    "Html": {"Data": html_content, "Charset": "UTF-8"},
                    "Text": {"Data": text_content, "Charset": "UTF-8"},
                },
            },
        )
        print(f"  [ SES ] Standard email sent from {sender_header} to {to_recipients} (Cc: {cc_recipients}): '{subject}'")
        return True
    except Exception as e:
        print(f"  [ SES ERROR ] Failed to send SES email: {e}")
        return False


def send_brand_approval_email(
    to_email: str,
    organization_name: str,
    game_name: str,
    approval_token: str,
    organization_logo_url: Optional[str] = None,
    organizer_name: Optional[str] = None,
    capacity: Optional[int] = None,
    host_email: Optional[str] = None,
    invite_code: Optional[str] = None,
    audit_email: str = AUDIT_EMAIL,
) -> bool:
    """
    Sends a rich HTML brand authorization request email to corporate approvers via AWS SES.
    Embeds official logos as inline MIME CID attachments with DVAA™ branding and copies audit_email.
    """
    if not to_email:
        print("  [ SES ] No recipient email provided for brand approval. Skipping.")
        return False

    approval_url = f"{BASE_URL}/brand-approval.html?token={approval_token}"
    code_suffix = f" (Code: {invite_code})" if invite_code else ""
    subject = f"[Action Required] Authorize Brand Logo for \"{game_name}\"{code_suffix} 🏢 (DVAA™)"
    organizer_display = organizer_name or "Event Organizer"
    capacity_display = f"{capacity} Players" if capacity else "Team Event"
    host_attribution = f"{organizer_display} ({host_email})" if host_email else organizer_display

    dabhousie_logo_bytes, header_logo_src, org_logo_bytes, org_logo_src = _fetch_inline_logos(organization_logo_url)

    logo_preview_html = ""
    if organization_logo_url or org_logo_bytes:
        logo_preview_html = f"""
        <div style="background:#0f172a; border:1px solid #334155; border-radius:12px; padding:16px; text-align:center; margin-bottom:20px;">
          <div style="font-size:11px; font-weight:700; color:#94a3b8; text-transform:uppercase; letter-spacing:0.8px; margin-bottom:10px;">Submitted Corporate Logo Preview</div>
          <table align="center" cellpadding="0" cellspacing="0" border="0" style="margin:0 auto;">
            <tr>
              <td align="center" bgcolor="#ffffff" style="background:#ffffff; border-radius:10px; padding:10px 16px; box-shadow:0 4px 12px rgba(0,0,0,0.3);">
                <img src="{org_logo_src}" alt="{organization_name}" height="64" style="height:64px; max-height:64px; width:auto; max-width:200px; object-fit:contain; display:block; margin:0 auto;" />
              </td>
            </tr>
          </table>
          <div style="font-size:13px; font-weight:700; color:#f8fafc; margin-top:8px;">{organization_name}</div>
        </div>
        """

    html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Corporate Brand Authorization - {game_name}</title>
</head>
<body style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color:#080c14; color:#e2e8f0; margin:0; padding:20px 10px;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#080c14; margin:0; padding:0;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px; background:#111827; border:1px solid #374151; border-radius:16px; overflow:hidden; box-shadow:0 12px 32px rgba(0,0,0,0.6);">
          <tr>
            <td style="background:linear-gradient(135deg, #0B3D91 0%, #0f172a 100%); padding:28px 20px; text-align:center; border-bottom:3px solid #f59e0b;">
              <a href="{BASE_URL}" target="_blank" style="text-decoration:none; display:inline-block;">
                <img src="{header_logo_src}" alt="DabHousie" width="220" style="max-width:220px; height:auto; display:block; margin:0 auto 10px auto; border:0; outline:none;" />
              </a>
              <p style="margin:0 0 10px 0; color:#f59e0b; font-size:12px; font-weight:700; text-transform:uppercase; letter-spacing:1.5px;">Multiplayer Tambola &bull; Housie &bull; Bingo</p>
              <h1 style="margin:0; color:#ffffff; font-size:22px; font-weight:800; letter-spacing:0.3px;">🏢 Corporate Brand Authorization Request</h1>
              <div style="display:inline-block; background:rgba(56, 189, 248, 0.15); border:1px solid rgba(56, 189, 248, 0.4); border-radius:6px; padding:4px 10px; margin-top:8px; font-size:11.5px; font-weight:700; color:#38bdf8;">
                🔒 DVAA™ (Domain-Verified Automated Approval)
              </div>
              <p style="margin:8px 0 0 0; color:#93c5fd; font-size:15px; font-weight:600;">{game_name}</p>
            </td>
          </tr>

          <tr>
            <td style="padding:28px 24px;">
              <p style="margin:0 0 16px 0; font-size:15px; line-height:1.6; color:#e2e8f0;">Hello,</p>
              <p style="margin:0 0 20px 0; font-size:14.5px; line-height:1.6; color:#cbd5e1;">
                <strong>{host_attribution}</strong> has organized a DabHousie event and requested permission to display official corporate branding for <strong>{organization_name}</strong> on the event live card and public Hall of Fame.
              </p>

              {logo_preview_html}

              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0b1120; border:1px solid #1e293b; border-radius:12px; margin-bottom:24px;">
                <tr>
                  <td style="padding:16px 18px;">
                    <table width="100%" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Organization:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:13.5px; font-weight:700;" align="right">{organization_name}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Event Name:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:13.5px; font-weight:700;" align="right">{game_name}</td>
                      </tr>
                      {f'<tr><td style="padding:6px 0; color:#94a3b8; font-size:13px;">Game Code:</td><td style="padding:6px 0; color:#f59e0b; font-size:14px; font-weight:800; font-family:Courier,\'Courier New\',monospace; letter-spacing:1px;" align="right">{invite_code}</td></tr>' if invite_code else ''}
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Requested By:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:13.5px; font-weight:600;" align="right">{host_attribution}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Scale:</td>
                        <td style="padding:6px 0; color:#38bdf8; font-size:13.5px; font-weight:700;" align="right">{capacity_display}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Verification Standard:</td>
                        <td style="padding:6px 0; color:#22c55e; font-size:13px; font-weight:700;" align="right">DVAA™ Protected</td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0c203a; border:1px solid #1e40af; border-left:4px solid #38bdf8; border-radius:0 10px 10px 0; margin-bottom:24px;">
                <tr>
                  <td style="padding:14px 16px;">
                    <div style="color:#38bdf8; font-size:13.5px; font-weight:700; margin-bottom:4px;">🔒 DVAA™ (Domain-Verified Automated Approval):</div>
                    <div style="color:#cbd5e1; font-size:12.5px; line-height:1.5;">
                      DabHousie protects your brand identity against impersonation. The game may proceed privately, but official corporate emblems and company name will appear publicly only upon your authorization.
                    </div>
                  </td>
                </tr>
              </table>

              <table cellpadding="0" cellspacing="0" border="0" align="center" style="margin:20px auto 0 auto;">
                <tr>
                  <td align="center" bgcolor="#f59e0b" style="background-color:#f59e0b; border-radius:10px; border:1px solid #d97706; padding:0;">
                    <a href="{approval_url}" target="_blank" style="background-color:#f59e0b; color:#0f172a !important; display:inline-block; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:15px; font-weight:800; text-decoration:none; padding:15px 36px; border-radius:10px; line-height:1.2; letter-spacing:0.3px;">
                      Authorize Corporate Branding &rarr;
                    </a>
                  </td>
                </tr>
              </table>

              <p style="margin:20px 0 0 0; text-align:center; font-size:12px; color:#64748b;">
                Or paste this secure link into your browser:<br>
                <a href="{approval_url}" target="_blank" style="color:#38bdf8; font-size:11.5px; word-break:break-all;">{approval_url}</a>
              </p>
            </td>
          </tr>

          <tr>
            <td style="padding:22px 24px; background:#0b1120; border-top:1px solid #1f2937; text-align:center; font-size:12px; color:#94a3b8; line-height:1.6;">
              <p style="margin:0 0 6px 0; color:#cbd5e1; font-weight:600;">🛡️ <strong>Zero-PII Architecture</strong> &bull; Link expires automatically in 7 days.</p>
              <p style="margin:0 0 6px 0; color:#94a3b8; font-size:11px;">📋 Audit copy dispatched to DabHousie Compliance ({audit_email}) for brand safety.</p>
              <p style="margin:0 0 6px 0;">Don't recognize this event? <a href="{approval_url}" target="_blank" style="color:#f87171; text-decoration:underline;">Decline Request</a></p>
              <p style="margin:0;">DabHousie &bull; <a href="{BASE_URL}" target="_blank" style="color:#38bdf8; text-decoration:none;">www.dabhousie.com</a> &bull; Support: <a href="mailto:{FROM_EMAIL}" style="color:#38bdf8; text-decoration:none;">{FROM_EMAIL}</a></p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"""

    text_content = f"""Corporate Brand Authorization Request for "{game_name}" (DVAA™)

Organization: {organization_name}
Event Name: {game_name}
Game Code: {invite_code or 'N/A'}
Requested By: {host_attribution}
Scale: {capacity_display}
Standard: DVAA™ (Domain-Verified Automated Approval)

{organizer_display} has scheduled this event and requested official corporate branding.
To review and authorize display of your brand logo on the event card and public Hall of Fame, please open:

{approval_url}

This secure authorization link expires in 7 days.
An audit copy has been dispatched to {audit_email}.
If you did not request this, you may safely decline or ignore this email.

Support: {FROM_EMAIL}
DabHousie - www.dabhousie.com
"""

    return _dispatch_ses_mime_or_standard(
        to_email=to_email,
        subject=subject,
        html_content=html_content,
        text_content=text_content,
        dabhousie_logo_bytes=dabhousie_logo_bytes,
        org_logo_bytes=org_logo_bytes,
        audit_email=audit_email,
    )


def send_brand_acknowledgement_email(
    to_email: str,
    organization_name: str,
    game_name: str,
    organization_logo_url: Optional[str] = None,
    organizer_name: Optional[str] = None,
    capacity: Optional[int] = None,
    host_email: Optional[str] = None,
    invite_code: Optional[str] = None,
    audit_email: str = AUDIT_EMAIL,
) -> bool:
    """
    Sends an automated acknowledgement email upon Instant Domain-Owner DVAA™ Auto-Approval.
    Always copies audit_email (contact@dabhousie.com) for immutable compliance tracking.
    """
    if not to_email:
        print("  [ SES ] No recipient email provided for brand acknowledgement. Skipping.")
        return False

    join_url = f"{BASE_URL}/#/join/{invite_code}" if invite_code else BASE_URL
    subject = f"Confirmed: Corporate Brand Verified & Activated for \"{game_name}\" 🏢 (DVAA™)"
    organizer_display = organizer_name or "Event Organizer"
    capacity_display = f"{capacity} Players" if capacity else "Team Event"
    host_attribution = f"{organizer_display} ({host_email})" if host_email else organizer_display

    dabhousie_logo_bytes, header_logo_src, org_logo_bytes, org_logo_src = _fetch_inline_logos(organization_logo_url)

    logo_preview_html = ""
    if organization_logo_url or org_logo_bytes:
        logo_preview_html = f"""
        <div style="background:#0f172a; border:1px solid #334155; border-radius:12px; padding:16px; text-align:center; margin-bottom:20px;">
          <div style="font-size:11px; font-weight:700; color:#94a3b8; text-transform:uppercase; letter-spacing:0.8px; margin-bottom:10px;">Official Activated Logo</div>
          <table align="center" cellpadding="0" cellspacing="0" border="0" style="margin:0 auto;">
            <tr>
              <td align="center" bgcolor="#ffffff" style="background:#ffffff; border-radius:10px; padding:10px 16px; box-shadow:0 4px 12px rgba(0,0,0,0.3);">
                <img src="{org_logo_src}" alt="{organization_name}" height="64" style="height:64px; max-height:64px; width:auto; max-width:200px; object-fit:contain; display:block; margin:0 auto;" />
              </td>
            </tr>
          </table>
          <div style="font-size:13px; font-weight:700; color:#f8fafc; margin-top:8px;">{organization_name}</div>
        </div>
        """

    html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Corporate Brand Activated - {game_name}</title>
</head>
<body style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color:#080c14; color:#e2e8f0; margin:0; padding:20px 10px;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#080c14; margin:0; padding:0;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px; background:#111827; border:1px solid #374151; border-radius:16px; overflow:hidden; box-shadow:0 12px 32px rgba(0,0,0,0.6);">
          <tr>
            <td style="background:linear-gradient(135deg, #065f46 0%, #0f172a 100%); padding:28px 20px; text-align:center; border-bottom:3px solid #10b981;">
              <a href="{BASE_URL}" target="_blank" style="text-decoration:none; display:inline-block;">
                <img src="{header_logo_src}" alt="DabHousie" width="220" style="max-width:220px; height:auto; display:block; margin:0 auto 10px auto; border:0; outline:none;" />
              </a>
              <p style="margin:0 0 10px 0; color:#34d399; font-size:12px; font-weight:700; text-transform:uppercase; letter-spacing:1.5px;">Corporate Brand Verification Confirmed</p>
              <h1 style="margin:0; color:#ffffff; font-size:22px; font-weight:800; letter-spacing:0.3px;">✅ Brand Activated &amp; Verified</h1>
              <div style="display:inline-block; background:rgba(16, 185, 129, 0.2); border:1px solid rgba(16, 185, 129, 0.5); border-radius:6px; padding:4px 10px; margin-top:8px; font-size:11.5px; font-weight:700; color:#6ee7b7;">
                🔒 DVAA™ Domain-Verified Automated Approval
              </div>
              <p style="margin:8px 0 0 0; color:#a7f3d0; font-size:15px; font-weight:600;">{game_name}</p>
            </td>
          </tr>

          <tr>
            <td style="padding:28px 24px;">
              <p style="margin:0 0 16px 0; font-size:15px; line-height:1.6; color:#e2e8f0;">Hello {organizer_display},</p>
              <p style="margin:0 0 20px 0; font-size:14.5px; line-height:1.6; color:#cbd5e1;">
                This email serves as an official confirmation that corporate branding for <strong>{organization_name}</strong> has been verified and activated for your event under DabHousie's <strong>DVAA™ (Domain-Verified Automated Approval)</strong> protocol.
              </p>

              {logo_preview_html}

              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0b1120; border:1px solid #1e293b; border-radius:12px; margin-bottom:24px;">
                <tr>
                  <td style="padding:16px 18px;">
                    <table width="100%" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Organization:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:13.5px; font-weight:700;" align="right">{organization_name}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Event Name:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:13.5px; font-weight:700;" align="right">{game_name}</td>
                      </tr>
                      {f'<tr><td style="padding:6px 0; color:#94a3b8; font-size:13px;">Game Code:</td><td style="padding:6px 0; color:#f59e0b; font-size:14px; font-weight:800; letter-spacing:1px;" align="right">{invite_code}</td></tr>' if invite_code else ''}
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Authorized By:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:13.5px; font-weight:600;" align="right">{host_attribution}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Event Capacity:</td>
                        <td style="padding:6px 0; color:#38bdf8; font-size:13.5px; font-weight:700;" align="right">{capacity_display}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Branding Status:</td>
                        <td style="padding:6px 0; color:#10b981; font-size:13px; font-weight:800;" align="right">ACTIVE &amp; APPROVED ✅</td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#064e3b; border:1px solid #059669; border-left:4px solid #10b981; border-radius:0 10px 10px 0; margin-bottom:24px;">
                <tr>
                  <td style="padding:14px 16px;">
                    <div style="color:#6ee7b7; font-size:13.5px; font-weight:700; margin-bottom:4px;">🔒 DVAA™ Instant Verification Compliance:</div>
                    <div style="color:#e2e8f0; font-size:12.5px; line-height:1.5;">
                      Because your authenticated host account is verified under <strong>@{to_email.split('@')[-1] if '@' in to_email else 'corporate domain'}</strong>, your event qualifies for instant brand activation. Your official badge is now live on game cards, waiting rooms, and the public Hall of Fame.
                    </div>
                  </td>
                </tr>
              </table>

              <table cellpadding="0" cellspacing="0" border="0" align="center" style="margin:20px auto 0 auto;">
                <tr>
                  <td align="center" bgcolor="#10b981" style="background-color:#10b981; border-radius:10px; border:1px solid #059669; padding:0;">
                    <a href="{join_url}" target="_blank" style="background-color:#10b981; color:#ffffff !important; display:inline-block; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:15px; font-weight:800; text-decoration:none; padding:15px 36px; border-radius:10px; line-height:1.2; letter-spacing:0.3px;">
                      Launch Event &amp; View Live Card &rarr;
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <tr>
            <td style="padding:22px 24px; background:#0b1120; border-top:1px solid #1f2937; text-align:center; font-size:12px; color:#94a3b8; line-height:1.6;">
              <p style="margin:0 0 6px 0; color:#cbd5e1; font-weight:600;">🛡️ <strong>Zero-PII Architecture</strong> &bull; Verified via DVAA™ Protocol.</p>
              <p style="margin:0 0 6px 0; color:#94a3b8; font-size:11px;">📋 Immutable compliance record delivered to DabHousie Compliance ({audit_email}).</p>
              <p style="margin:0;">DabHousie &bull; <a href="{BASE_URL}" target="_blank" style="color:#38bdf8; text-decoration:none;">www.dabhousie.com</a> &bull; Support: <a href="mailto:{FROM_EMAIL}" style="color:#38bdf8; text-decoration:none;">{FROM_EMAIL}</a></p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"""

    text_content = f"""Confirmed: Corporate Brand Verified & Activated for "{game_name}" (DVAA™)

Organization: {organization_name}
Event Name: {game_name}
Game Code: {invite_code or 'N/A'}
Authorized By: {host_attribution}
Scale: {capacity_display}
Status: ACTIVE & APPROVED ✅
Verification: DVAA™ (Domain-Verified Automated Approval)

Corporate branding for {organization_name} has been verified and activated for this event.
Your official logo and company badge are now active on the event live card, player tickets, and Hall of Fame.

Join / View Event: {join_url}

Compliance Audit: An immutable verification record has been archived and delivered to {audit_email}.

Support: {FROM_EMAIL}
DabHousie - www.dabhousie.com
"""

    return _dispatch_ses_mime_or_standard(
        to_email=to_email,
        subject=subject,
        html_content=html_content,
        text_content=text_content,
        dabhousie_logo_bytes=dabhousie_logo_bytes,
        org_logo_bytes=org_logo_bytes,
        audit_email=audit_email,
    )


def send_brand_approved_confirmation_email(
    to_email: str,
    organization_name: str,
    game_name: str,
    organization_logo_url: Optional[str] = None,
    organizer_name: Optional[str] = None,
    capacity: Optional[int] = None,
    host_email: Optional[str] = None,
    approver_email: Optional[str] = None,
    approved_at: Optional[str] = None,
    approved_ip: Optional[str] = None,
    invite_code: Optional[str] = None,
    audit_email: str = AUDIT_EMAIL,
) -> bool:
    """
    Sends an automated audit confirmation email once an external approver clicks 'Approve'.
    Delivers full meeting details to contact@dabhousie.com, the approver, and the host.
    """
    join_url = f"{BASE_URL}/#/join/{invite_code}" if invite_code else BASE_URL
    subject = f"[DVAA™ Audit] Corporate Brand Approved & Live: \"{game_name}\" ✅"
    organizer_display = organizer_name or "Event Organizer"
    capacity_display = f"{capacity} Players" if capacity else "Team Event"
    host_attribution = f"{organizer_display} ({host_email})" if host_email else organizer_display
    approver_display = approver_email or to_email
    timestamp_display = approved_at or "Just now"
    ip_display = approved_ip or "Web Verification"

    dabhousie_logo_bytes, header_logo_src, org_logo_bytes, org_logo_src = _fetch_inline_logos(organization_logo_url)

    logo_preview_html = ""
    if organization_logo_url or org_logo_bytes:
        logo_preview_html = f"""
        <div style="background:#0f172a; border:1px solid #334155; border-radius:12px; padding:16px; text-align:center; margin-bottom:20px;">
          <div style="font-size:11px; font-weight:700; color:#94a3b8; text-transform:uppercase; letter-spacing:0.8px; margin-bottom:10px;">Approved Corporate Emblem</div>
          <table align="center" cellpadding="0" cellspacing="0" border="0" style="margin:0 auto;">
            <tr>
              <td align="center" bgcolor="#ffffff" style="background:#ffffff; border-radius:10px; padding:10px 16px; box-shadow:0 4px 12px rgba(0,0,0,0.3);">
                <img src="{org_logo_src}" alt="{organization_name}" height="64" style="height:64px; max-height:64px; width:auto; max-width:200px; object-fit:contain; display:block; margin:0 auto;" />
              </td>
            </tr>
          </table>
          <div style="font-size:13px; font-weight:700; color:#f8fafc; margin-top:8px;">{organization_name}</div>
        </div>
        """

    html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Brand Approved Audit Record - {game_name}</title>
</head>
<body style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color:#080c14; color:#e2e8f0; margin:0; padding:20px 10px;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#080c14; margin:0; padding:0;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px; background:#111827; border:1px solid #374151; border-radius:16px; overflow:hidden; box-shadow:0 12px 32px rgba(0,0,0,0.6);">
          <tr>
            <td style="background:linear-gradient(135deg, #0B3D91 0%, #065f46 100%); padding:28px 20px; text-align:center; border-bottom:3px solid #10b981;">
              <a href="{BASE_URL}" target="_blank" style="text-decoration:none; display:inline-block;">
                <img src="{header_logo_src}" alt="DabHousie" width="220" style="max-width:220px; height:auto; display:block; margin:0 auto 10px auto; border:0; outline:none;" />
              </a>
              <p style="margin:0 0 10px 0; color:#34d399; font-size:12px; font-weight:700; text-transform:uppercase; letter-spacing:1.5px;">DVAA™ Audit &bull; Brand Approval Confirmed</p>
              <h1 style="margin:0; color:#ffffff; font-size:22px; font-weight:800; letter-spacing:0.3px;">✅ Brand Approved &amp; Published</h1>
              <div style="display:inline-block; background:rgba(16, 185, 129, 0.2); border:1px solid rgba(16, 185, 129, 0.5); border-radius:6px; padding:4px 10px; margin-top:8px; font-size:11.5px; font-weight:700; color:#6ee7b7;">
                🔒 DVAA™ Domain-Verified Automated Approval
              </div>
              <p style="margin:8px 0 0 0; color:#93c5fd; font-size:15px; font-weight:600;">{game_name}</p>
            </td>
          </tr>

          <tr>
            <td style="padding:28px 24px;">
              <p style="margin:0 0 16px 0; font-size:15px; line-height:1.6; color:#e2e8f0;">
                Official Notice: Corporate brand authorization for <strong>{organization_name}</strong> was approved by <strong>{approver_display}</strong>.
              </p>

              {logo_preview_html}

              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0b1120; border:1px solid #1e293b; border-radius:12px; margin-bottom:24px;">
                <tr>
                  <td style="padding:16px 18px;">
                    <div style="font-size:12px; font-weight:700; color:#38bdf8; text-transform:uppercase; letter-spacing:0.8px; margin-bottom:12px;">Meeting &amp; Event Audit Details</div>
                    <table width="100%" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Organization:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:13.5px; font-weight:700;" align="right">{organization_name}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Event Name:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:13.5px; font-weight:700;" align="right">{game_name}</td>
                      </tr>
                      {f'<tr><td style="padding:6px 0; color:#94a3b8; font-size:13px;">Game Code:</td><td style="padding:6px 0; color:#f59e0b; font-size:14px; font-weight:800; letter-spacing:1px;" align="right">{invite_code}</td></tr>' if invite_code else ''}
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Event Organizer:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:13.5px; font-weight:600;" align="right">{host_attribution}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Corporate Approver:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:13.5px; font-weight:700;" align="right">{approver_display}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Event Scale:</td>
                        <td style="padding:6px 0; color:#38bdf8; font-size:13.5px; font-weight:700;" align="right">{capacity_display}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Approval Timestamp:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:12.5px;" align="right">{timestamp_display}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Audit Verification IP:</td>
                        <td style="padding:6px 0; color:#94a3b8; font-size:12px; font-family:monospace;" align="right">{ip_display}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Hall of Fame Display:</td>
                        <td style="padding:6px 0; color:#10b981; font-size:13px; font-weight:800;" align="right">PUBLISHED &amp; LIVE ✅</td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <table cellpadding="0" cellspacing="0" border="0" align="center" style="margin:20px auto 0 auto;">
                <tr>
                  <td align="center" bgcolor="#0B3D91" style="background-color:#0B3D91; border-radius:10px; border:1px solid #3b82f6; padding:0;">
                    <a href="{join_url}" target="_blank" style="background-color:#0B3D91; color:#ffffff !important; display:inline-block; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:15px; font-weight:800; text-decoration:none; padding:15px 36px; border-radius:10px; line-height:1.2; letter-spacing:0.3px;">
                      View Live Event Room &rarr;
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <tr>
            <td style="padding:22px 24px; background:#0b1120; border-top:1px solid #1f2937; text-align:center; font-size:12px; color:#94a3b8; line-height:1.6;">
              <p style="margin:0 0 6px 0; color:#cbd5e1; font-weight:600;">🛡️ <strong>Zero-PII Compliance Trail</strong> &bull; Powered by DVAA™.</p>
              <p style="margin:0 0 6px 0; color:#94a3b8; font-size:11px;">📋 Permanent audit record delivered to DabHousie Compliance ({audit_email}).</p>
              <p style="margin:0;">DabHousie &bull; <a href="{BASE_URL}" target="_blank" style="color:#38bdf8; text-decoration:none;">www.dabhousie.com</a> &bull; Support: <a href="mailto:{FROM_EMAIL}" style="color:#38bdf8; text-decoration:none;">{FROM_EMAIL}</a></p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"""

    text_content = f"""Brand Approved Audit Record for "{game_name}" (DVAA™)

Organization: {organization_name}
Event Name: {game_name}
Game Code: {invite_code or 'N/A'}
Organizer: {host_attribution}
Approver: {approver_display}
Approved At: {timestamp_display}
Audit IP: {ip_display}
Capacity: {capacity_display}
Status: PUBLISHED & LIVE ✅

Official corporate branding for {organization_name} is now live in the event room and DabHousie Hall of Fame.
Join Link: {join_url}

An immutable audit record has been archived and delivered to {audit_email}.

Support: {FROM_EMAIL}
DabHousie - www.dabhousie.com
"""

    return _dispatch_ses_mime_or_standard(
        to_email=to_email,
        subject=subject,
        html_content=html_content,
        text_content=text_content,
        dabhousie_logo_bytes=dabhousie_logo_bytes,
        org_logo_bytes=org_logo_bytes,
        audit_email=audit_email,
        extra_to=host_email,
    )


def send_winner_gift_email(
    to_email: str,
    player_name: str,
    game_name: str,
    invite_code: str,
    prize_type: str,
    verification_code: str,
    prize_value: Optional[float] = None,
    brand_name: Optional[str] = None,
    gift_title: Optional[str] = None,
    product_url: Optional[str] = None,
    fulfilled_code: Optional[str] = None,
    brand_logo_url: Optional[str] = None,
    audit_email: str = AUDIT_EMAIL,
) -> bool:
    """
    Sends a rich HTML Prize & Sponsored Brand Gift Voucher email to a game winner.
    """
    if not to_email:
        print("  [ SES ] No recipient email provided for winner gift email. Skipping.")
        return False

    prize_label = (prize_type or "Prize").replace("_", " ").title()
    val_str = f"${float(prize_value):.2f}".replace(".00", "") if prize_value and float(prize_value) > 0 else ""
    val_badge = f" ({val_str} Value)" if val_str else ""
    gift_display = gift_title or f"{prize_label} Winner Award"
    brand_display = brand_name or "DabHousie Official Event"
    cta_url = product_url if (product_url and product_url.startswith("http")) else f"{BASE_URL}/#/rewards"
    cta_label = f"Explore {brand_name} Product & Redeem ↗" if (brand_name and product_url) else "View in My Rewards Dashboard →"

    subject = f"🏆 You Won {prize_label}{val_badge} in \"{game_name}\"! ({gift_display})"

    dabhousie_logo_bytes, header_logo_src, org_logo_bytes, org_logo_src = _fetch_inline_logos(brand_logo_url)

    brand_box_html = ""
    if brand_name or gift_title:
        logo_img_html = ""
        if brand_logo_url or org_logo_bytes:
            logo_img_html = f"""
            <table align="center" cellpadding="0" cellspacing="0" border="0" style="margin:0 auto 12px auto;">
              <tr>
                <td align="center" bgcolor="#ffffff" style="background:#ffffff; border-radius:10px; padding:8px 14px; box-shadow:0 4px 12px rgba(0,0,0,0.25);">
                  <img src="{org_logo_src}" alt="{brand_display}" height="48" style="height:48px; max-height:48px; width:auto; max-width:160px; object-fit:contain; display:block; margin:0 auto;" />
                </td>
              </tr>
            </table>
            """
        voucher_row_html = ""
        if fulfilled_code:
            voucher_row_html = f"""
            <div style="margin-top:14px; padding:12px; background:#064e3b; border:1px dashed #10b981; border-radius:8px;">
              <div style="font-size:11px; color:#6ee7b7; font-weight:700; text-transform:uppercase; letter-spacing:0.8px;">Redemption / Promo Voucher Code</div>
              <div style="font-size:18px; color:#ffffff; font-family:Courier,'Courier New',monospace; font-weight:800; letter-spacing:1.5px; margin-top:4px;">{fulfilled_code}</div>
            </div>
            """
        brand_box_html = f"""
        <div style="background:linear-gradient(135deg, #1e1b4b 0%, #0f172a 100%); border:1px solid #6366f1; border-radius:14px; padding:20px; text-align:center; margin-bottom:24px;">
          <div style="font-size:11px; font-weight:800; color:#a5b4fc; text-transform:uppercase; letter-spacing:1.2px; margin-bottom:10px;">🎁 Sponsored Brand Gift Awarded</div>
          {logo_img_html}
          <div style="font-size:18px; font-weight:800; color:#ffffff; margin-bottom:4px;">{gift_display}</div>
          <div style="font-size:13px; color:#c7d2fe; font-weight:600;">Sponsored by {brand_display}{val_badge}</div>
          {voucher_row_html}
        </div>
        """

    html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Your DabHousie Winner Award - {game_name}</title>
</head>
<body style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color:#080c14; color:#e2e8f0; margin:0; padding:20px 10px;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#080c14; margin:0; padding:0;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px; background:#111827; border:1px solid #374151; border-radius:16px; overflow:hidden; box-shadow:0 12px 32px rgba(0,0,0,0.6);">
          <tr>
            <td style="background:linear-gradient(135deg, #0B3D91 0%, #0f172a 100%); padding:28px 20px; text-align:center; border-bottom:3px solid #f59e0b;">
              <a href="{BASE_URL}" target="_blank" style="text-decoration:none; display:inline-block;">
                <img src="{header_logo_src}" alt="DabHousie" width="220" style="max-width:220px; height:auto; display:block; margin:0 auto 10px auto; border:0; outline:none;" />
              </a>
              <p style="margin:0 0 10px 0; color:#f59e0b; font-size:12px; font-weight:700; text-transform:uppercase; letter-spacing:1.5px;">Official Winner Certificate &amp; Gift Voucher</p>
              <h1 style="margin:0; color:#ffffff; font-size:22px; font-weight:800;">🏆 Congratulations, {player_name}!</h1>
              <p style="margin:8px 0 0 0; color:#93c5fd; font-size:15px; font-weight:600;">{game_name} (Code: {invite_code})</p>
            </td>
          </tr>
          <tr>
            <td style="padding:28px 24px;">
              <p style="margin:0 0 20px 0; font-size:14.5px; line-height:1.6; color:#cbd5e1;">
                Your winning claim for <strong>{prize_label}</strong> has been officially verified on the DabHousie Zero-Trust Ledger! Below are your prize and brand gift details.
              </p>

              {brand_box_html}

              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0b1120; border:1px solid #1e293b; border-radius:12px; margin-bottom:24px;">
                <tr>
                  <td style="padding:16px 18px;">
                    <table width="100%" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Winner Name:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:13.5px; font-weight:700;" align="right">{player_name}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Prize Category:</td>
                        <td style="padding:6px 0; color:#f59e0b; font-size:14px; font-weight:800;" align="right">🏆 {prize_label}</td>
                      </tr>
                      {f'<tr><td style="padding:6px 0; color:#94a3b8; font-size:13px;">Prize Value:</td><td style="padding:6px 0; color:#10b981; font-size:14px; font-weight:800;" align="right">{val_str}</td></tr>' if val_str else ''}
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Verification Code:</td>
                        <td style="padding:6px 0; color:#38bdf8; font-size:13.5px; font-weight:800; font-family:Courier,'Courier New',monospace;" align="right">{verification_code}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <table cellpadding="0" cellspacing="0" border="0" align="center" style="margin:20px auto 0 auto;">
                <tr>
                  <td align="center" bgcolor="#f59e0b" style="background-color:#f59e0b; border-radius:10px; border:1px solid #d97706; padding:0;">
                    <a href="{cta_url}" target="_blank" style="background-color:#f59e0b; color:#0f172a !important; display:inline-block; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:15px; font-weight:800; text-decoration:none; padding:15px 32px; border-radius:10px; line-height:1.2;">
                      {cta_label}
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:20px 24px; background:#0b1120; border-top:1px solid #1f2937; text-align:center; font-size:12px; color:#94a3b8; line-height:1.6;">
              <p style="margin:0 0 6px 0;">View all your event rewards anytime at <a href="{BASE_URL}/#/rewards" style="color:#38bdf8; text-decoration:none;">www.dabhousie.com/#/rewards</a></p>
              <p style="margin:0;">DabHousie &bull; Support: <a href="mailto:{FROM_EMAIL}" style="color:#38bdf8; text-decoration:none;">{FROM_EMAIL}</a></p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"""

    text_content = f"""Congratulations {player_name}! You won {prize_label}{val_badge} in {game_name} (Code: {invite_code})!

Prize Awarded: {gift_display} ({brand_display})
Verification Code: {verification_code}
{f'Voucher / Promo Code: {fulfilled_code}' if fulfilled_code else ''}
Product / Redemption Link: {cta_url}

View your rewards dashboard: {BASE_URL}/#/rewards
"""

    return _dispatch_ses_mime_or_standard(
        to_email=to_email,
        subject=subject,
        html_content=html_content,
        text_content=text_content,
        dabhousie_logo_bytes=dabhousie_logo_bytes,
        org_logo_bytes=org_logo_bytes,
        audit_email=audit_email,
    )


def send_brand_offer_registered_email(
    to_email: str,
    marketer_name: str,
    brand_name: str,
    gift_title: str,
    retail_value: float,
    organizer_price: float,
    product_url: str,
    promo_code: Optional[str] = None,
    brand_logo_url: Optional[str] = None,
    vouchers_total_count: int = 10,
    target_region: str = "Global",
    currency: str = "USD",
    audit_email: str = PARTNERSHIPS_EMAIL,
) -> bool:
    """
    Sends a thank-you & pending-approval confirmation email from partnerships@dabhousie.com
    to a Brand Marketing representative when they submit a partner offer.
    """
    if not to_email:
        return False

    subject = f"🤝 Thank You for Sponsoring a DabHousie Brand Offer: {brand_name} — {gift_title} (Pending Approval)"
    dabhousie_logo_bytes, header_logo_src, org_logo_bytes, org_logo_src = _fetch_inline_logos(brand_logo_url)
    host_cost_label = "$0.00 (100% Brand Sponsored)" if float(organizer_price or 0) == 0 else f"${float(organizer_price):.2f}"

    logo_preview_html = ""
    if brand_logo_url or org_logo_bytes:
        logo_preview_html = f"""
        <div style="background:#0f172a; border:1px solid #334155; border-radius:12px; padding:14px; text-align:center; margin-bottom:18px;">
          <table align="center" cellpadding="0" cellspacing="0" border="0" style="margin:0 auto;">
            <tr>
              <td align="center" bgcolor="#ffffff" style="background:#ffffff; border-radius:10px; padding:8px 14px;">
                <img src="{org_logo_src}" alt="{brand_name}" height="48" style="height:48px; max-height:48px; width:auto; max-width:180px; object-fit:contain; display:block; margin:0 auto;" />
              </td>
            </tr>
          </table>
          <div style="font-size:13px; font-weight:700; color:#f8fafc; margin-top:8px;">{brand_name}</div>
        </div>
        """

    html_content = f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Thank You for Partnering With DabHousie</title></head>
<body style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color:#080c14; color:#e2e8f0; margin:0; padding:20px 10px;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px; margin:0 auto; background:#111827; border:1px solid #374151; border-radius:16px; overflow:hidden;">
    <tr>
      <td style="background:linear-gradient(135deg, #0B3D91 0%, #0f172a 100%); padding:26px 20px; text-align:center; border-bottom:3px solid #f59e0b;">
        <img src="{header_logo_src}" alt="DabHousie" width="200" style="max-width:200px; height:auto; display:block; margin:0 auto 10px auto;" />
        <p style="margin:0 0 8px 0; color:#f59e0b; font-size:12px; font-weight:700; text-transform:uppercase; letter-spacing:1.3px;">DabHousie Brand Marketing Partner Program</p>
        <h1 style="margin:0; color:#ffffff; font-size:21px; font-weight:800;">🤝 Thank You for Sponsoring a Brand Offer!</h1>
        <p style="margin:6px 0 0 0; color:#93c5fd; font-size:14px; font-weight:600;">{brand_name} &bull; {gift_title}</p>
        <div style="display:inline-block; background:rgba(245, 158, 11, 0.18); border:1px solid rgba(245, 158, 11, 0.45); border-radius:6px; padding:4px 10px; margin-top:10px; font-size:11.5px; font-weight:700; color:#fcd34d;">
          ⏳ Status: Submitted &amp; Waiting for Approval
        </div>
      </td>
    </tr>
    <tr>
      <td style="padding:24px;">
        <p style="margin:0 0 14px 0; font-size:14.5px; color:#e2e8f0; line-height:1.6;">
          Hello <strong>{marketer_name}</strong>,
        </p>
        <p style="margin:0 0 16px 0; font-size:14.5px; color:#cbd5e1; line-height:1.6;">
          <strong>Thank you for partnering with DabHousie and sponsoring a promotional reward for {brand_name}!</strong> We truly appreciate your support in making live multiplayer Housie &amp; Bingo events even more exciting for players around the world.
        </p>
        <p style="margin:0 0 18px 0; font-size:14px; color:#cbd5e1; line-height:1.6;">
          Your <strong>{vouchers_total_count}-reward pilot offer</strong> has been received and is currently <strong>waiting for approval</strong> by our Brand Partnerships team. Once verified and approved, your offer will appear in the <strong>DabHousie Partner Catalog</strong> and <strong>Host Gift Catalog</strong> so event organizers can assign your reward to winning game tiers.
        </p>
        {logo_preview_html}
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0b1120; border:1px solid #1e293b; border-radius:12px; margin-bottom:20px;">
          <tr>
            <td style="padding:16px;">
              <div style="font-size:12px; font-weight:700; color:#f59e0b; text-transform:uppercase; letter-spacing:0.8px; margin-bottom:10px;">Submitted Pilot Offer Summary</div>
              <div style="font-size:13px; color:#94a3b8; margin-bottom:6px;">Brand Partner: <strong style="color:#ffffff;">{brand_name}</strong></div>
              <div style="font-size:13px; color:#94a3b8; margin-bottom:6px;">Offer Title: <strong style="color:#ffffff;">{gift_title}</strong></div>
              <div style="font-size:13px; color:#94a3b8; margin-bottom:6px;">Offer Retail Value: <strong style="color:#34d399;">{currency} ${retail_value:.2f}</strong></div>
              <div style="font-size:13px; color:#94a3b8; margin-bottom:6px;">Reward Sponsorship / Host Cost: <strong style="color:#38bdf8;">{host_cost_label}</strong></div>
              <div style="font-size:13px; color:#94a3b8; margin-bottom:6px;">Pilot Batch Quantity: <strong style="color:#ffffff;">{vouchers_total_count} rewards</strong></div>
              <div style="font-size:13px; color:#94a3b8; margin-bottom:6px;">Target Region: <strong style="color:#ffffff;">{target_region}</strong></div>
              <div style="font-size:13px; color:#94a3b8; margin-bottom:6px;">Approval Status: <strong style="color:#fcd34d;">⏳ Waiting for Approval</strong></div>
              <div style="font-size:13px; color:#94a3b8;">Brand Landing Page: <a href="{product_url}" style="color:#38bdf8;">{product_url}</a></div>
            </td>
          </tr>
        </table>
        <table cellpadding="0" cellspacing="0" border="0" align="center" style="margin:18px auto 0 auto;">
          <tr>
            <td align="center" bgcolor="#f59e0b" style="background-color:#f59e0b; border-radius:10px; padding:0;">
              <a href="{BASE_URL}/brand-partners.html" target="_blank" style="background-color:#f59e0b; color:#0f172a !important; display:inline-block; font-size:14px; font-weight:800; text-decoration:none; padding:13px 28px; border-radius:10px;">
                View Brand Marketing Partner Program &rarr;
              </a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
    <tr>
      <td style="padding:18px 24px; background:#0b1120; border-top:1px solid #1f2937; text-align:center; font-size:12px; color:#94a3b8; line-height:1.6;">
        Questions or updates to your campaign? Reply directly to <a href="mailto:{PARTNERSHIPS_EMAIL}" style="color:#38bdf8; text-decoration:none;">{PARTNERSHIPS_EMAIL}</a><br>
        DabHousie Partnerships &bull; <a href="{BASE_URL}" style="color:#38bdf8; text-decoration:none;">www.dabhousie.com</a>
      </td>
    </tr>
  </table>
</body>
</html>
"""
    text_content = f"""Hello {marketer_name},

Thank you for partnering with DabHousie and sponsoring a promotional reward for {brand_name}!

Your {vouchers_total_count}-reward pilot offer ({gift_title}) has been submitted and is currently waiting for approval by our Brand Partnerships team. Once approved, it will appear in the DabHousie Partner Catalog and Host Gift Catalog.

Offer Summary:
- Brand Partner: {brand_name}
- Offer Title: {gift_title}
- Retail Value: {currency} ${retail_value:.2f}
- Reward Sponsorship / Host Cost: {host_cost_label}
- Pilot Batch Quantity: {vouchers_total_count} rewards
- Target Region: {target_region}
- Status: Waiting for Approval
- Brand Landing Page: {product_url}

Questions? Contact us at {PARTNERSHIPS_EMAIL}
DabHousie Brand Marketing Partner Program: {BASE_URL}/brand-partners.html
"""
    return _dispatch_ses_mime_or_standard(
        to_email=to_email,
        subject=subject,
        html_content=html_content,
        text_content=text_content,
        dabhousie_logo_bytes=dabhousie_logo_bytes,
        org_logo_bytes=org_logo_bytes,
        audit_email=audit_email,
        from_email=PARTNERSHIPS_EMAIL,
        from_display_name="DabHousie Partnerships",
    )
