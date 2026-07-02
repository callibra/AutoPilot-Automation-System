import os
import sys
import datetime
import cv2
import asyncio
import telegram
import json
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, CallbackQuery
from telegram.ext import Application, CallbackQueryHandler, ContextTypes
from telegram.error import RetryAfter, TelegramError, TimedOut
from pathlib import Path

# APP ROOT 
if getattr(sys, 'frozen', False):
    APP_ROOT = Path(sys.executable).parent
else:
    APP_ROOT = Path(__file__).parent

LAST_AUDIT_ALERT = {}
# === LOAD CONFIG FROM JSON ===
CONFIG_PATH = APP_ROOT / "JSON" / "settings.json"

if not os.path.exists(CONFIG_PATH):
    raise RuntimeError(f"❌ Config file does not exist: {CONFIG_PATH}")

with open(CONFIG_PATH, "r", encoding="utf-8-sig") as f:
    config = json.load(f)

BOT_TOKEN = config.get("BOT_TOKEN")
CHAT_ID = int(config.get("CHAT_ID"))
OWNER_IDS = set(int(x) for x in config.get("OWNER_IDS", []))
AUTOPILOT_URL = config.get("AUTOPILOT_URL")

if not BOT_TOKEN or not CHAT_ID:
    raise RuntimeError("❌ BOT_TOKEN or CHAT_ID is missing in config.json")

CURRENT_MODE = "camera"
# === BASE PATH (exe-safe) ===
BASE_DIR = APP_ROOT
FOLDER = os.path.join(BASE_DIR, "Camera")
SCREEN_FOLDER = os.path.join(BASE_DIR, "Archive/Recordings")
LOG_FOLDER = os.path.join(BASE_DIR, "Autopilot_Data", "DataFolder_Logs")

PAGE_SIZE = 5
VIDEO_RETENTION_DAYS = int(config.get("VIDEO_RETENTION_DAYS", 15))
LOG_RETENTION_DAYS = 30

# ✅ Kreiranje na folderi (sekogas, i vo EXE)
os.makedirs(LOG_FOLDER, exist_ok=True)
  
# Funkcija za Log_File
def write_audit_log(message: str):
    """Zapisi vo Log_File."""
    now = datetime.datetime.now()
    log_filename = os.path.join(LOG_FOLDER, f"audit_{now.strftime('%Y-%m-%d')}.txt")
    with open(log_filename, "a", encoding="utf-8") as f:
        f.write(f"{now.strftime('%Y-%m-%d %H:%M:%S')} | {message}\n")
    cleanup_old_logs()

def cleanup_old_logs():
    """Brisenje na Logovi posteri od 30 dena."""
    now = datetime.datetime.now()
    for f in os.listdir(LOG_FOLDER):
        path = os.path.join(LOG_FOLDER, f)
        if os.path.isfile(path):
            created_time = datetime.datetime.fromtimestamp(os.path.getctime(path))
            if (now - created_time).days > LOG_RETENTION_DAYS:
                os.remove(path)    

# Funkcija za Video Folder Info
def get_video_info(path):
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        return "⏱ Unknown"
    fps = cap.get(cv2.CAP_PROP_FPS)
    frames = cap.get(cv2.CAP_PROP_FRAME_COUNT)
    duration = frames / fps if fps > 0 else 0
    cap.release()
    return str(datetime.timedelta(seconds=int(duration)))

def get_total_folder_size(folder_path):
    total_bytes = 0
    for f in os.listdir(folder_path):
        path = os.path.join(folder_path, f)
        if os.path.isfile(path):
            total_bytes += os.path.getsize(path)
    if total_bytes < 1024**2:
        return f"{total_bytes / 1024:.2f} KB"
    elif total_bytes < 1024**3:
        return f"{total_bytes / (1024**2):.2f} MB"
    else:
        return f"{total_bytes / (1024**3):.2f} GB"

# === 🛡️ SECURITY GATE ===
async def check_security(obj):
    
    # --- CASE 1: CallbackQuery direktno ---
    if isinstance(obj, CallbackQuery):
        user = obj.from_user
        message = obj.message
        text = obj.data or ""
        async def send_method(msg): await message.reply_text(msg)

    # --- CASE 2: Update со callback_query ---
    elif isinstance(obj, Update) and obj.callback_query:
        cq = obj.callback_query
        user = cq.from_user
        message = cq.message
        text = cq.data or ""
        async def send_method(msg): await message.reply_text(msg)

    # --- CASE 3: Update со message ---
    elif isinstance(obj, Update) and obj.message:
        user = obj.message.from_user
        message = obj.message
        text = obj.message.text or ""
        async def send_method(msg): await message.reply_text(msg)

    else:
        return False  # unsupported object

    user_id = user.id
    chat_id = message.chat.id
    chat_type = message.chat.type

    # Private chat check
    if chat_type != "private":
        log = f"Message from non-private chat | ChatType={chat_type} | ChatId={chat_id}"
        print(f"AUDIT: {log}")
        write_audit_log(f"AUDIT: {log}")
        return False

    # Owner check
    if user_id not in OWNER_IDS:
        now = datetime.datetime.now()
        log = f"Unauthorized access | UserId={user_id} | ChatId={chat_id} | Text='{text}'"
        print(f"AUDIT: {log}")
        write_audit_log(f"AUDIT: {log}")

        last_alert_time = LAST_AUDIT_ALERT.get(user_id)
        if not last_alert_time or (now - last_alert_time).total_seconds() >= 180:
            alert_text = (
                "🛡️ SECURITY ALERT 🛡️\n"
                "Unauthorized attempt to access!\n\n"
                f"👨‍💼 UserId: {user_id}\n"
                f"🆔 ChatId: {chat_id}\n"
                f"📨 Message: '{text}'\n"
                f"🕒 Time: {now.strftime('%d-%m-%Y %H:%M:%S')}"
            )
            await send_method(alert_text)
            LAST_AUDIT_ALERT[user_id] = now

        await send_method("Chat access ⛔ not Allowed.")
        return False

    return True

# === Funkcija za prikaz na stranata ===
async def show_page(update_or_query, context, page: int):
    # SECURITY CHECK
    if not await check_security(update_or_query):
        return

    # helper za reply/edit
    if hasattr(update_or_query, "message"):
        reply = update_or_query.message.reply_text
        edit = None
    else:
        reply = update_or_query.message.reply_text
        edit = getattr(update_or_query, "edit_message_text", None)

    # ✅ Logiranje za pristap
    user_id = update_or_query.message.from_user.id if hasattr(update_or_query, "message") else update_or_query.from_user.id
    write_audit_log(f"User {user_id} use the media folder page {page+1}")

    # ✅ Auto-create folder if not exists
    mode = context.user_data.get("mode", "camera")
    active_folder = SCREEN_FOLDER if mode == "screen" else FOLDER

    folder_created = False
    if not os.path.exists(active_folder):
        os.makedirs(active_folder, exist_ok=True)
        folder_created = True
        write_audit_log(f"Folder {active_folder} has been created.")

    files = [
        f for f in os.listdir(active_folder)
        if os.path.isfile(os.path.join(active_folder, f))
    ]

    folder_label = "Camera" if mode == "camera" else "Recordings"
    if not files:
        if folder_created:
            text = (
                f"🗂️ New folder created:\n{active_folder}\n\n"
                "ℹ️ The folder is empty."
            )
        else:
            text = (
                f"🗂️ {folder_label} Media Folder\n\n"
                "ℹ️ The folder is empty.\n\n"
                "🎦 No videos have been saved yet."
            )
        markup = InlineKeyboardMarkup([
            [InlineKeyboardButton("✅ Menu", callback_data="main_menu")],
            [InlineKeyboardButton("🚪 Exit", callback_data="exit")]
        ])
        await reply(text, reply_markup=markup, parse_mode="Markdown")
        return

    # === Auto delete videos older than VIDEO_RETENTION_DAYS ===
    now = datetime.datetime.now()
    for f in files:
        path = os.path.join(active_folder, f)
        created = datetime.datetime.fromtimestamp(os.path.getctime(path))
        if (now - created).days > VIDEO_RETENTION_DAYS:
            os.remove(path)
            message = (
            f"Old 🎬 videos automatically 🗑️ deleted: {f}\n"
            f"📅 Created on: {created.strftime('%Y-%m-%d %H:%M:%S')}\n"
            f"⚠️ Status: Video older than {VIDEO_RETENTION_DAYS} days\n"
            f"🕒 Today: {now.strftime('%Y-%m-%d %H:%M:%S')}"
            )
            write_audit_log(message)
            await context.bot.send_message(
                chat_id=CHAT_ID,
                text=message
            )

    # Refresh file list and sort by creation date
    files = sorted(
        [f for f in os.listdir(active_folder) if os.path.isfile(os.path.join(active_folder, f))],
        key=lambda x: os.path.getctime(os.path.join(active_folder, x)),
        reverse=True
    )

    total = len(files)
    # ✅ FIX: korekcija na stranica po brishenje
    max_page = max(0, (total - 1) // PAGE_SIZE)
    if page > max_page:
        page = max_page    
    start = page * PAGE_SIZE
    end = start + PAGE_SIZE
    page_files = files[start:end]
    # Zapisi momentalna stranica vo user_data
    context.user_data["current_page"] = page

    # === Header ===
    created_now = datetime.datetime.now()
    total_size_text = get_total_folder_size(active_folder)
    folder_label = "Camera" if mode == "camera" else "Recordings"
    header_text = (
        f"🗂️ FOLDER ({folder_label})  🧾 Page {page+1} from {(total-1)//PAGE_SIZE + 1}\n\n"
        f"🕒 {created_now.strftime('%H:%M:%S - %d-%m-%Y')}\n\n"
        f"💾 *Total folder size:* {total_size_text}\n\n"
        f"📀 *Total number of videos:* {total}\n\n"
    )
    await reply(header_text, parse_mode="Markdown")

    # === Sekoe video: text + Play/Delete ===
    for idx, f in enumerate(page_files, start=start + 1):
        path = os.path.join(active_folder, f)
        created = datetime.datetime.fromtimestamp(os.path.getctime(path))
        duration = get_video_info(path)
        size_bytes = os.path.getsize(path)
        if size_bytes < 1024**2:
            size_text = f"{size_bytes / 1024:.2f} KB"
        elif size_bytes < 1024**3:
            size_text = f"{size_bytes / (1024**2):.2f} MB"
        else:
            size_text = f"{size_bytes / (1024**3):.2f} GB"
        text = (
            f"*{idx}. {f}*\n"
            f"📅 *Creation date:* {created.strftime('%Y-%m-%d')}\n"
            f"🕒 *Creation time:* {created.strftime('%H:%M:%S')}\n"
            f"⏱ *Duration:* {duration}\n"
            f"💾 *Size:* {size_text}"
        )
        keyboard = [[
            InlineKeyboardButton("▶️ Play", callback_data=f"play|{f}"),
            InlineKeyboardButton("🗑 Delete", callback_data=f"del|{f}")
        ]]
        markup = InlineKeyboardMarkup(keyboard)
        await reply(text, reply_markup=markup, parse_mode="Markdown")

    # === Footer: pagination + Media + Izlez ===
    nav_buttons = []
    if start > 0:
        nav_buttons.append(InlineKeyboardButton("⬅️ Prev", callback_data=f"page|{page-1}"))
    if end < total:
        nav_buttons.append(InlineKeyboardButton("Next ➡️", callback_data=f"page|{page+1}"))
        nav_buttons.append(InlineKeyboardButton("Last ⏭️", callback_data=f"page|{(total-1)//PAGE_SIZE}"))

    nav_buttons.append(InlineKeyboardButton("🗂️ Folder", callback_data="data_command"))
    nav_buttons.append(InlineKeyboardButton("✅ Menu", callback_data="main_menu"))
    exit_button = [InlineKeyboardButton("🚪 Exit", callback_data="exit")]
    footer_markup = InlineKeyboardMarkup([nav_buttons, exit_button])
    footer_text = f"🎬 Display from {start+1} to {min(end, total)} from {total} videos"
    await reply(footer_text, reply_markup=footer_markup)

# === /data komanda ===
async def data_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_security(update):
        return
    await show_main_menu(update, context)
    
# Global per-user processing flag
user_processing = {}
# === Callback handler ===
async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    global VIDEO_RETENTION_DAYS   # ✅ First
    query = update.callback_query
    user_id = query.from_user.id
    
    # 1. SECURITY FIRST
    if not await check_security(query):
        return
    
    # MODE CHANGE HANDLER
    if query.data.startswith("mode|"):
        mode = query.data.split("|")[1]
        context.user_data["mode"] = mode
        context.user_data["current_page"] = 0
        await query.answer()
        await show_page(query, context, page=0)
        return
    
    # 3. GET MODE AFTER SECURITY
    mode = context.user_data.get("mode", "camera")
    active_folder = SCREEN_FOLDER if mode == "screen" else FOLDER
    
    # MEDIA BUTTON (FIX - MOVED HERE)
    if query.data == "data_command":
        await query.answer()
        page = context.user_data.get("current_page", 0)
        await show_page(query, context, page)
        return
    
    if query.data == "retention":
        await query.answer()
        keyboard = [
            [InlineKeyboardButton("7 Days", callback_data="ret|7")],
            [InlineKeyboardButton("15 Days", callback_data="ret|15")],
            [InlineKeyboardButton("30 Days", callback_data="ret|30")],
            [InlineKeyboardButton("60 Days", callback_data="ret|60")],
            [InlineKeyboardButton("✅ Menu", callback_data="main_menu")],
            [InlineKeyboardButton("🚪 Exit", callback_data="exit")]
        ]
        await query.message.reply_text(
            f"📅 Current retention: {VIDEO_RETENTION_DAYS} days",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
        return    
    
    if query.data.startswith("ret|"):
        await query.answer()
        days = int(query.data.split("|")[1])
        VIDEO_RETENTION_DAYS = days
        config["VIDEO_RETENTION_DAYS"] = days
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=4)
        write_audit_log(
            f"Video retention changed to {days} days by user {query.from_user.id}"
        )
        await query.message.reply_text(
            f"✅ Video retention changed to {days} days"
        )
        await show_main_menu(query, context)   # 🔥 BACK TO MAIN MENU
        return
    
    # USER LOCK CHECK
    if user_processing.get(user_id, False):
        try:
            await query.answer("⌛ Processing previous command, Please wait a moment…", show_alert=True)
        except TelegramError:
            pass
        return
    
    # Active User
    user_processing[user_id] = True
    last_markup = query.message.reply_markup if query.message.reply_markup else None
    try:
        # Remove keyboard
        try:
            await query.message.edit_reply_markup(reply_markup=None)
        except TelegramError:
            pass

        # PLAY / DELETE alert
        if query.data.startswith(("play|", "del|")):
            try:
                await query.answer("⌛ Executing command…", show_alert=True)
            except TelegramError:
                pass

        # PLAY VIDEO
        if query.data.startswith("play|"):
            parts = query.data.split("|", 1)
            if len(parts) != 2:
                await query.message.reply_text("❌ Request failed.")
                return

            filename = os.path.basename(parts[1])
            path = os.path.join(active_folder, filename)
            real_path = os.path.realpath(path)
            real_base = os.path.realpath(active_folder)

            if os.path.commonpath([real_path, real_base]) != real_base:
                await query.message.reply_text("❌ Path failed.")
                return

            if not os.path.exists(real_path):
                await query.message.reply_text("❌ File does not exist.")
                write_audit_log(f"Missing file requested: {filename} by user {query.from_user.id}")
                write_audit_log(f"You attempted to start a video that does not exist: {filename} from user {query.from_user.id}")
                return

            status_msg = await query.message.reply_text("⌛ The video is Loading…")
            upload_success = False
            last_error = None

            async def send_file():
                """Core upload logic separated for clarity."""
                file_size = os.path.getsize(real_path)
                # Open file safely per request
                with open(real_path, "rb") as f:
                    # Large file → document
                    if file_size > 50 * 1024 * 1024:
                        return await query.message.reply_document(document=f)
                    # Small file → video
                    else:
                        return await query.message.reply_video(video=f)
            # Optional retry loop (safe + simple)
            for attempt in range(1, 3):  # 2 attempts max
                try:
                    await send_file()
                    upload_success = True
                    last_error = None
                    break

                except (asyncio.TimeoutError, TimedOut, httpx.ReadTimeout) as e:
                    last_error = f"Timeout error (attempt {attempt}): {e}"
                    await asyncio.sleep(1.5)

                except RetryAfter as e:
                    last_error = f"Rate limited: retry after {e.retry_after}s"
                    await asyncio.sleep(e.retry_after)

                except TelegramError as e:
                    last_error = f"Telegram API error: {e}"
                    break

                except Exception as e:
                    last_error = f"Unexpected error: {e}"
                    break

            # Final status handling
            if upload_success:
                await status_msg.edit_text("✅ Video sent successfully")
                write_audit_log(
                    f"Video sent: {filename} by user {query.from_user.id}"
                )
            else:
                await status_msg.edit_text(f"❌ Failed to send video:\n{last_error}")
                write_audit_log(
                    f"Video send FAILED: {filename} | Error: {last_error} | User {query.from_user.id}"
                )

        # DELETE VIDEO
        elif query.data.startswith("del|"):
            parts = query.data.split("|", 1)
            if len(parts) != 2:
                await query.message.reply_text("❌ Request failed.")
                return

            filename = os.path.basename(parts[1])
            path = os.path.join(active_folder, filename)
            real_path = os.path.realpath(path)
            real_base = os.path.realpath(active_folder)

            if os.path.commonpath([real_path, real_base]) != real_base:
                await query.message.reply_text("❌ Path failed.")
                return

            if not os.path.exists(real_path):
                await query.message.reply_text("❌ File does not exist.")
                write_audit_log(
                    f"You attempted to delete a missing video: {filename} from user {query.from_user.id}"
                )
            else:
                try:
                    os.remove(real_path)
                    current_page = context.user_data.get("current_page", 0)
                    await show_page(query, context, current_page)
                    await query.message.reply_text(
                        f"🗑️ Video deleted\n\n🎬 File: {filename}\n\n✅ The video has been successfully removed."
                    )
                    write_audit_log(
                        f"Manually deleted video: {filename} from user {query.from_user.id}"
                    )
                except PermissionError:
                    await query.message.reply_text(
                        f"❌ Cannot delete {filename} - file is currently in use."
                    )
                    write_audit_log(
                        f"Delete blocked (file in use): {filename} from user {query.from_user.id}"
                    )
                except Exception as e:
                    await query.message.reply_text("❌ Delete failed.")

                    write_audit_log(
                        f"Delete failed: {filename} | Error: {e} | User {query.from_user.id}"
                    )

        # MAIN MENU
        elif query.data == "main_menu":
            context.user_data["current_page"] = 0
            context.user_data["mode"] = "camera"
            await query.answer()
            await show_main_menu(query, context)
            return

    finally:
        # Reset User
        user_processing.pop(user_id, None)
        if last_markup:
            try:
                await query.message.edit_reply_markup(reply_markup=last_markup)
            except TelegramError:
                pass

    # PAGE NAVIGATION
    if query.data.startswith("page|"):
        page = int(query.data.split("|")[1])
        await show_page(query, context, page)

    elif query.data == "exit":
        keyboard = [[InlineKeyboardButton("👉 Return to AutoPilot", url=AUTOPILOT_URL)]]
        await query.message.reply_text(
            "🚪 DATA Server has been Stopped...",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
        os._exit(0)

# === Funkcija za start meni ===
async def send_start_menu(application: Application):
    MENU_TEXT = "💿  *DATA System Started*  ✅"
    MAIN_MENU = InlineKeyboardMarkup([
        [InlineKeyboardButton("📷 Camera Video", callback_data="mode|camera")],
        [InlineKeyboardButton("🖥️ Recordings Video", callback_data="mode|screen")],  #  Comment for 1 Folder
        [InlineKeyboardButton("⚙️ Retention Days", callback_data="retention")],
        [InlineKeyboardButton("🚪 Exit", callback_data="exit")]
    ])
    await application.bot.send_message(chat_id=CHAT_ID, text=MENU_TEXT, reply_markup=MAIN_MENU, parse_mode="Markdown")

async def show_main_menu(update_or_query, context):
    MAIN_MENU = InlineKeyboardMarkup([
        [InlineKeyboardButton("📷 Camera Video", callback_data="mode|camera")],
        [InlineKeyboardButton("🖥️ Recordings Video", callback_data="mode|screen")],  #  Comment for 1 Folder
        [InlineKeyboardButton("⚙️ Retention Days", callback_data="retention")],
        [InlineKeyboardButton("🚪 Exit", callback_data="exit")]
    ])

    text = "💿  *DATA System Menu*  ✅"
    if hasattr(update_or_query, "message"):
        await update_or_query.message.reply_text(
            text,
            reply_markup=MAIN_MENU,
            parse_mode="Markdown"
        )
    else:
        await update_or_query.message.reply_text(
            text,
            reply_markup=MAIN_MENU,
            parse_mode="Markdown"
        )

# === Main ===
app = (
    Application.builder()
    .token(BOT_TOKEN)
    .connect_timeout(30)
    .read_timeout(60)
    .write_timeout(60)
    .pool_timeout(30)
    .post_init(send_start_menu)
    .build()
)
app.add_handler(CallbackQueryHandler(button_handler, pattern=r"^mode\|"))
app.add_handler(CallbackQueryHandler(button_handler, pattern=r"^(play|del|page)\|"))
app.add_handler(CallbackQueryHandler(button_handler, pattern=r"^exit$"))
# 🔥 CATCH ALL
app.add_handler(CallbackQueryHandler(button_handler))
print("✅ DATA Server has started Running...")
write_audit_log(f"✅ DATA Server has started Running...")
app.run_polling()

######################################################################## Camera Script End.
# C:\Users\*****\AppData\Local\Python\pythoncore-x.xx-xx\Scripts - Path

# C:\Users\*****\AppData\Local\Python\bin - Path

############  PIP Install  ##############
# pip list - Lista na instalirani paketi

# pip install python-telegram-bot==20.3

# pip install opencv-python

############ .EXE COMPYLER  Install  ##############
# pip install pyinstaller ttkbootstrap pillow ZA.EXE FILE COMPILER

# pyinstaller --noconsole --onefile --windowed --add-data "media;media" --add-data "JSON;JSON" CommandsEditor.py  - CommandsEditor.exe

# pyinstaller --noconsole --onefile --windowed --add-data "media;media" --add-data "JSON;JSON" ScriptsEditor.py  - ScriptsEditor.exe

# pyinstaller --noconsole --onefile Camera.py  - Camera.exe

