# backend/functions/email_ses.py
# DabHousie — Amazon SES Email Dispatcher
# Sends automated, branded purchase receipts and notification emails

import os
import urllib.request
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.image import MIMEImage
from typing import Optional

try:
    import boto3
    from botocore.exceptions import ClientError
except ImportError:
    boto3 = None
    ClientError = Exception

SES_REGION = os.getenv("AWS_SES_REGION", os.getenv("AWS_REGION", "us-east-2"))
FROM_EMAIL = os.getenv("SES_FROM_EMAIL", os.getenv("SUPPORT_EMAIL", "receipts@dabhousie.com"))
BASE_URL = os.getenv("BASE_URL", "https://www.dabhousie.com")


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


def send_brand_approval_email(
    to_email: str,
    organization_name: str,
    game_name: str,
    approval_token: str,
    organization_logo_url: Optional[str] = None,
    organizer_name: Optional[str] = None,
    capacity: Optional[int] = None,
    host_email: Optional[str] = None,
) -> bool:
    """
    Sends a rich HTML brand authorization request email to corporate approvers via AWS SES.
    Embeds official logos as inline MIME CID attachments so Microsoft Outlook, Gmail, and
    Apple Mail render images automatically without 'Download pictures' blocking.
    """
    if not to_email:
        print("  [ SES ] No recipient email provided for brand approval. Skipping.")
        return False

    approval_url = f"{BASE_URL}/brand-approval.html?token={approval_token}"
    subject = f"Action Required: Authorize Brand Logo for \"{game_name}\" 🏢"
    organizer_display = organizer_name or "Event Organizer"
    capacity_display = f"{capacity} Players" if capacity else "Team Event"
    host_attribution = f"{organizer_display} ({host_email})" if host_email else organizer_display

    # Track attached inline images
    attached_cids = {}

    # 1. Load DabHousie logo for inline CID embedding
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

    # 2. Fetch Corporate Logo for inline CID embedding
    org_logo_bytes = None
    if organization_logo_url:
        try:
            req = urllib.request.Request(organization_logo_url, headers={"User-Agent": "Mozilla/5.0 (DabHousie-SES)"})
            with urllib.request.urlopen(req, timeout=4) as resp:
                org_logo_bytes = resp.read()
        except Exception as e:
            print(f"  [ SES ] Could not fetch org logo for inline CID: {e}")

    org_logo_src = "cid:logo_org" if org_logo_bytes else organization_logo_url

    logo_preview_html = ""
    if organization_logo_url or org_logo_bytes:
        logo_preview_html = f"""
        <div style="background:#0f172a; border:1px solid #334155; border-radius:12px; padding:16px; text-align:center; margin-bottom:20px;">
          <div style="font-size:11px; font-weight:700; color:#94a3b8; text-transform:uppercase; letter-spacing:0.8px; margin-bottom:10px;">Submitted Corporate Logo Preview</div>
          <div style="display:inline-block; background:#ffffff; border-radius:10px; padding:12px 20px; box-shadow:0 4px 12px rgba(0,0,0,0.3);">
            <img src="{org_logo_src}" alt="{organization_name}" style="max-height:48px; max-width:200px; object-fit:contain; display:block; margin:0 auto;" />
          </div>
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
          <!-- Header with Official DabHousie Logo -->
          <tr>
            <td style="background:linear-gradient(135deg, #0B3D91 0%, #0f172a 100%); padding:28px 20px; text-align:center; border-bottom:3px solid #f59e0b;">
              <a href="{BASE_URL}" target="_blank" style="text-decoration:none; display:inline-block;">
                <img src="{header_logo_src}" alt="DabHousie" width="220" style="max-width:220px; height:auto; display:block; margin:0 auto 10px auto; border:0; outline:none;" />
              </a>
              <p style="margin:0 0 12px 0; color:#f59e0b; font-size:12px; font-weight:700; text-transform:uppercase; letter-spacing:1.5px;">Multiplayer Tambola &bull; Housie &bull; Bingo</p>
              <h1 style="margin:0; color:#ffffff; font-size:22px; font-weight:800; letter-spacing:0.3px;">🏢 Corporate Brand Authorization Request</h1>
              <p style="margin:6px 0 0 0; color:#93c5fd; font-size:15px; font-weight:600;">{game_name}</p>
            </td>
          </tr>

          <!-- Main Content Body -->
          <tr>
            <td style="padding:28px 24px;">
              <p style="margin:0 0 16px 0; font-size:15px; line-height:1.6; color:#e2e8f0;">
                Hello,
              </p>
              <p style="margin:0 0 20px 0; font-size:14.5px; line-height:1.6; color:#cbd5e1;">
                <strong>{host_attribution}</strong> has organized a DabHousie event and requested to display official corporate branding for <strong>{organization_name}</strong> on the event live card and public Hall of Fame.
              </p>

              <!-- Logo Preview Box -->
              {logo_preview_html}

              <!-- Event Details Grid -->
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
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Requested By:</td>
                        <td style="padding:6px 0; color:#f8fafc; font-size:13.5px; font-weight:600;" align="right">{host_attribution}</td>
                      </tr>
                      <tr>
                        <td style="padding:6px 0; color:#94a3b8; font-size:13px;">Scale:</td>
                        <td style="padding:6px 0; color:#38bdf8; font-size:13.5px; font-weight:700;" align="right">{capacity_display}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Trust Callout -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0c203a; border:1px solid #1e40af; border-left:4px solid #38bdf8; border-radius:0 10px 10px 0; margin-bottom:24px;">
                <tr>
                  <td style="padding:14px 16px;">
                    <div style="color:#38bdf8; font-size:13.5px; font-weight:700; margin-bottom:4px;">🔒 Domain-Verified Automated Approval (DVAA):</div>
                    <div style="color:#cbd5e1; font-size:12.5px; line-height:1.5;">
                      DabHousie protects your brand identity against unauthorized use. The gameplay can proceed, but official badges and company logos appear publicly only upon your authorization.
                    </div>
                  </td>
                </tr>
              </table>

              <!-- Bulletproof CTA Button -->
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

          <!-- Footer / Trust Badges & Abuse Report -->
          <tr>
            <td style="padding:22px 24px; background:#0b1120; border-top:1px solid #1f2937; text-align:center; font-size:12px; color:#94a3b8; line-height:1.6;">
              <p style="margin:0 0 6px 0; color:#cbd5e1; font-weight:600;">🛡️ <strong>Zero-PII Architecture</strong> &bull; Link expires automatically in 7 days.</p>
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

    text_content = f"""Corporate Brand Authorization Request for "{game_name}"

Organization: {organization_name}
Event Name: {game_name}
Requested By: {host_attribution}
Scale: {capacity_display}

{organizer_display} has scheduled this event and requested official corporate branding.
To review and authorize display of your brand logo on the event card and public Hall of Fame, please open:

{approval_url}

This secure authorization link expires in 7 days.
If you did not request this, you may safely decline or ignore this email.

Support: {FROM_EMAIL}
DabHousie - www.dabhousie.com
"""

    if boto3 is None:
        print(f"  [ SES (Dev / Log Mode) ] Brand approval email simulated to {to_email} for '{organization_name}'.")
        return True

    try:
        ses_client = boto3.client("ses", region_name=SES_REGION)

        # Prefer raw email with inline MIME attachments for perfect Outlook rendering
        if dabhousie_logo_bytes or org_logo_bytes:
            try:
                msg_root = MIMEMultipart("related")
                msg_root["Subject"] = subject
                msg_root["From"] = f"DabHousie <{FROM_EMAIL}>"
                msg_root["To"] = to_email

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
                    Source=f"DabHousie <{FROM_EMAIL}>",
                    Destinations=[to_email],
                    RawMessage={"Data": msg_root.as_string()},
                )
                print(f"  [ SES ] Brand approval email (raw MIME CID) successfully sent to {to_email}")
                return True
            except Exception as e_raw:
                print(f"  [ SES WARNING ] Raw MIME dispatch failed, falling back to standard send_email: {e_raw}")

        # Fallback to standard SES send_email
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
        print(f"  [ SES ] Brand approval email successfully sent to {to_email}")
        return True
    except Exception as e:
        print(f"  [ SES ERROR ] Failed to send brand approval email: {e}")
        return False



