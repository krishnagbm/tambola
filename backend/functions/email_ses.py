# backend/functions/email_ses.py
# DabHousie — Amazon SES Email Dispatcher
# Sends automated, branded purchase receipts and notification emails

import os
from typing import Optional

try:
    import boto3
    from botocore.exceptions import ClientError
except ImportError:
    boto3 = None
    ClientError = Exception

SES_REGION = os.getenv("AWS_SES_REGION", os.getenv("AWS_REGION", "us-east-1"))
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

      <a href="{BASE_URL}/#/wallet" class="btn">Go to My DabHousie Wallet →</a>
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
    Sends the Private Party join link and list of single-use Seat OTPs to the organizer.
    """
    if not to_email:
        print("  [ SES ] No recipient email provided. Skipping email dispatch.")
        return False

    subject = f"Private Party Access Codes: {game_name} (Code: {invite_code})"
    join_url = f"{BASE_URL}/#/join/{invite_code}"

    otp_rows_html = ""
    otp_rows_text = ""
    for idx, item in enumerate(otps_list, 1):
        seat_num = item.get("seat_number", idx) if isinstance(item, dict) else idx
        otp_code = item.get("otp_code", item) if isinstance(item, dict) else str(item)
        otp_rows_html += f"""
        <div style="display:flex; justify-content:space-between; align-items:center; padding:8px 12px; margin-bottom:6px; background:#161b22; border:1px solid #30363d; border-radius:8px;">
          <span style="font-weight:600; color:#94a3b8; font-size:13px;">Seat #{seat_num}</span>
          <span style="font-family:monospace; font-size:16px; font-weight:700; letter-spacing:2px; color:#38bdf8; background:#0f172a; padding:4px 10px; border-radius:6px; border:1px solid #1e293b;">{otp_code}</span>
        </div>
        """
        otp_rows_text += f"Seat #{seat_num}: Passcode {otp_code}\n"

    html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Private Party Passcodes - {game_name}</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background-color: #0d1117;
      color: #e6edf3;
      margin: 0;
      padding: 24px;
    }}
    .container {{
      max-width: 600px;
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
    .header h1 {{
      margin: 0;
      color: #ffffff;
      font-size: 22px;
      font-weight: 700;
    }}
    .header p {{
      margin: 6px 0 0 0;
      color: #FFC107;
      font-size: 14px;
      font-weight: 600;
    }}
    .content {{
      padding: 28px 24px;
    }}
    .info-card {{
      background: #0d1117;
      border: 1px solid #30363d;
      border-radius: 12px;
      padding: 16px;
      margin-bottom: 20px;
    }}
    .btn {{
      display: inline-block;
      background: linear-gradient(135deg, #FFC107 0%, #FF9800 100%);
      color: #000000;
      text-decoration: none;
      font-weight: 700;
      font-size: 15px;
      padding: 12px 24px;
      border-radius: 8px;
      margin: 12px 0 20px 0;
      text-align: center;
    }}
    .instructions {{
      background: #0f172a;
      border-left: 4px solid #38bdf8;
      padding: 14px 16px;
      border-radius: 0 8px 8px 0;
      margin-bottom: 20px;
      font-size: 13.5px;
      line-height: 1.5;
    }}
    .footer {{
      background: #0d1117;
      border-top: 1px solid #21262d;
      padding: 18px 24px;
      text-align: center;
      font-size: 12px;
      color: #8b949e;
    }}
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🔒 Private Party Access Passcodes</h1>
      <p>{game_name}</p>
    </div>
    <div class="content">
      <div class="info-card">
        <div style="font-size:13px; color:#8b949e; margin-bottom:4px;">Master Join Link</div>
        <div style="font-size:15px; font-weight:600; color:#f8fafc; word-break:break-all;">
          <a href="{join_url}" style="color:#38bdf8; text-decoration:underline;">{join_url}</a>
        </div>
        <div style="margin-top:10px; font-size:13px; color:#8b949e;">Party Code: <strong style="color:#FFC107; font-size:15px;">{invite_code}</strong> &bull; Seats: <strong>{len(otps_list)}</strong></div>
      </div>

      <div class="instructions">
        <strong>📌 How to Distribute to Your Team:</strong><br>
        1. Share the Master Join Link with your team.<br>
        2. Assign <strong>one unique passcode</strong> to each invited member.<br>
        3. Once a member enters their passcode, their seat is locked to their device. If an uninvited guest uses a passcode, that seat is claimed.
      </div>

      <h3 style="font-size:15px; color:#f1f5f9; margin-bottom:12px;">🎟️ Single-Use Seat Passcodes ({len(otps_list)} Total):</h3>
      <div style="max-height:360px; overflow-y:auto; padding-right:4px;">
        {otp_rows_html}
      </div>

      <div style="text-align:center; margin-top:20px;">
        <a href="{BASE_URL}/#/admin/lobby/{invite_code}" class="btn">Open Host Dashboard →</a>
      </div>
    </div>
    <div class="footer">
      DabHousie &bull; Zero-PII Private Entertainment<br>
      Questions or support? Contact <a href="mailto:{FROM_EMAIL}" style="color:#38bdf8;">{FROM_EMAIL}</a>
    </div>
  </div>
</body>
</html>
"""

    text_content = f"""Private Party Access Passcodes for {game_name}
Party Code: {invite_code}
Join Link: {join_url}
Total Seats: {len(otps_list)}

How to Distribute:
Share the join link and give one unique passcode to each member. Once entered, the seat is bound to that player.

Passcodes:
{otp_rows_text}

Host Dashboard: {BASE_URL}/#/admin/lobby/{invite_code}
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

