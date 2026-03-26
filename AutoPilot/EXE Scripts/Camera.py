import os
import sys
import datetime
import cv2
import asyncio
import httpx
import telegram
import json
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, CallbackQuery, InputFile
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, ContextTypes
from telegram.error import RetryAfter, TelegramError, TimedOut
import sys
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
CHAT_ID = config.get("CHAT_ID")
OWNER_IDS = set(int(x) for x in config.get("OWNER_IDS", []))
AUTOPILOT_URL = config.get("AUTOPILOT_URL")

if not BOT_TOKEN or not CHAT_ID:
    raise RuntimeError("❌ BOT_TOKEN or CHAT_ID is missing in config.json")

bot = telegram.Bot(token=BOT_TOKEN)

# === BASE PATH (exe-safe) ===
BASE_DIR = os.path.dirname(sys.executable)
FOLDER = os.path.join(BASE_DIR, "Camera")
LOG_FOLDER = os.path.join(BASE_DIR, "Autopilot_Data", "DataFolder_Logs")

PAGE_SIZE = 5
VIDEO_RETENTION_DAYS = 15
LOG_RETENTION_DAYS = 30

# ✅ Kreiranje na folderi (sekogas, i vo EXE)
os.makedirs(FOLDER, exist_ok=True)
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
                f"UserId: {user_id}\n"
                f"ChatId: {chat_id}\n"
                f"Message: '{text}'\n"
                f"Time: {now.strftime('%d-%m-%Y %H:%M:%S')}"
            )
            await send_method(alert_text)
            LAST_AUDIT_ALERT[user_id] = now

        await send_method("Chat access not Allowed.")
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
    folder_created = False
    if not os.path.exists(FOLDER):
        os.makedirs(FOLDER, exist_ok=True)
        folder_created = True
        write_audit_log(f"Folder {FOLDER} has been created.")

    files = [f for f in os.listdir(FOLDER) if os.path.isfile(os.path.join(FOLDER, f))]

    if folder_created:
        text = (
            "📂 Media folder has been created.\n\n"
            "ℹ️ The folder is empty.\n\n"
            "🎥 No videos have been saved yet."
        )
        markup = InlineKeyboardMarkup([[InlineKeyboardButton("🚪 Exit", callback_data="exit")]])
        await reply(text, reply_markup=markup, parse_mode="Markdown")
        return

    # === Auto delete videos older than VIDEO_RETENTION_DAYS ===
    now = datetime.datetime.now()
    for f in files:
        path = os.path.join(FOLDER, f)
        created = datetime.datetime.fromtimestamp(os.path.getctime(path))
        if (now - created).days > VIDEO_RETENTION_DAYS:
            os.remove(path)
            write_audit_log(f"Old videos automatically deleted: {f} (created on {created.strftime('%Y-%m-%d %H:%M:%S')})")

    # Refresh file list and sort by creation date
    files = sorted(
        [f for f in os.listdir(FOLDER) if os.path.isfile(os.path.join(FOLDER, f))],
        key=lambda x: os.path.getctime(os.path.join(FOLDER, x)),
        reverse=True
    )

    total = len(files)
    if not files:
        text = "📂 No videos in the folder."
        markup = InlineKeyboardMarkup([[InlineKeyboardButton("🚪 Exit", callback_data="exit")]])
        await reply(text, reply_markup=markup)
        return
        
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
    total_size_text = get_total_folder_size(FOLDER)
    header_text = (
        f"✅ MEDIA FOLDER | 📄 Page {page+1} from {(total-1)//PAGE_SIZE + 1}\n\n"
        f"🕒 {created_now.strftime('%H:%M:%S - %d-%m-%Y')}\n\n"
        f"💾 *Total folder size:* {total_size_text}\n\n"
        f"📄 *Total number of videos:* {total}\n\n"
    )
    await reply(header_text, parse_mode="Markdown")

    # === Sekoe video: text + Play/Delete ===
    for idx, f in enumerate(page_files, start=start + 1):
        path = os.path.join(FOLDER, f)
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

    nav_buttons.append(InlineKeyboardButton("📂 Media", callback_data="data_command"))
    exit_button = [InlineKeyboardButton("🚪 Exit", callback_data="exit")]

    footer_markup = InlineKeyboardMarkup([nav_buttons, exit_button])
    footer_text = f"📄 Display from {start+1} to {min(end, total)} from {total} videos"
    await reply(footer_text, reply_markup=footer_markup)

# === /data komanda ===
async def data_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_security(update):
        return
    await show_page(update, context, page=0)
    
# Global per-user processing flag
user_processing = {}

# TimeOut Internet
MAX_RETRIES = 3
TIMEOUT = 500  # secundi

# === Callback handler ===
async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    user_id = query.from_user.id

    if not await check_security(query):
        return

    # User Command Check
    if user_processing.get(user_id, False):
        try:
            await query.answer("⌛ Processing previous command, Please wait a moment…", show_alert=True)
        except:
            pass
        return

    # Active User
    user_processing[user_id] = True
    last_markup = query.message.reply_markup if query.message.reply_markup else None

    try:
        # Reply_markup
        try:
            await query.message.edit_reply_markup(reply_markup=None)
        except:
            pass

        # Play/Delete
        if query.data.startswith(("play|", "del|")):
            try:
                await query.answer("⌛ Executing command…", show_alert=True)
            except:
                pass

        # --- Play video ---
        if query.data.startswith("play|"):
            filename = query.data.split("|")[1]
            path = os.path.join(FOLDER, filename)

            if not os.path.exists(path):
                await query.message.reply_text("❌ File does not exist.")
                write_audit_log(f"You attempted to start a video that does not exist: {filename} from user {query.from_user.id}")
            else:
                status_msg = await query.message.reply_text("⌛ The video is Loading…")
                try:
                    with open(path, "rb") as f:
                        if os.path.getsize(path) > 50 * 1024 * 1024:
                            try:
                                await query.message.reply_document(document=InputFile(f))
                                upload_success = True
                            except (asyncio.TimeoutError, telegram.error.TimedOut, httpx.ReadTimeout) as exc:
                                upload_success = True
                                last_error = exc
                        else:
                            try:
                                await query.message.reply_video(video=InputFile(f))
                                upload_success = True
                            except (asyncio.TimeoutError, telegram.error.TimedOut, httpx.ReadTimeout) as exc:
                                upload_success = True
                                last_error = exc

                    if upload_success:
                        try:
                            await status_msg.edit_text("✅ Video Loading successful !")
                        except:
                            pass
                        write_audit_log(f"Video played: {filename} from user {query.from_user.id}")
                    else:
                        try:
                            await status_msg.edit_text(f"❌ Video Loading failed: {last_error}")
                        except:
                            pass
                        write_audit_log(f"Error sending video: {filename} from user {query.from_user.id} | Error: {last_error}")
                except Exception as e:
                    try:
                        await status_msg.edit_text(f"❌ Loading error: {e}")
                    except:
                        pass
                    write_audit_log(f"Error sending video: {filename} from user {query.from_user.id} | Error: {e}")

        # --- Delete video ---
        elif query.data.startswith("del|"):
            filename = query.data.split("|")[1]
            path = os.path.join(FOLDER, filename)

            if not os.path.exists(path):
                await query.message.reply_text("❌ File does not exist.")
                write_audit_log(f"You attempted to delete a video that does not exist: {filename} from user {query.from_user.id}")
            else:
                try:
                    os.remove(path)
                    current_page = context.user_data.get("current_page", 0)
                    await show_page(query, context, current_page)
                    await query.message.reply_text(
                        f"🗑 Delete:\n\n🎬 Video: {filename}\n\n✅ The video has been successfully deleted."
                    )
                    write_audit_log(f"Manually deleted video: {filename} from user {query.from_user.id}")
                except PermissionError:
                    await query.message.reply_text(f"❌ Cannot be deleted {filename} - the file is in use.")
                    write_audit_log(f"Attempt to delete video while in use: {filename} from user {query.from_user.id}")

    finally:
        # Reset User
        user_processing[user_id] = False
        if last_markup:
            try:
                await query.message.edit_reply_markup(reply_markup=last_markup)
            except:
                pass

    # === Page/Exit ===
    if query.data.startswith("page|"):
        page = int(query.data.split("|")[1])
        await show_page(query, context, page)
    elif query.data == "exit":
        keyboard = [[InlineKeyboardButton("👉 Return to AutoPilot", url=AUTOPILOT_URL)]]
        await query.message.reply_text("🚪 DATA Server has been Stopped...", reply_markup=InlineKeyboardMarkup(keyboard))
        os._exit(0)

# === Funkcija za start meni ===
async def send_start_menu(application: Application):
    MENU_TEXT = "✅ *Media folder* ✅"
    MAIN_MENU = InlineKeyboardMarkup([[InlineKeyboardButton("Media", callback_data="data_command")]])
    await application.bot.send_message(chat_id=CHAT_ID, text=MENU_TEXT, reply_markup=MAIN_MENU, parse_mode="Markdown")

# === Callback za MENI kopce ===
async def menu_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    if not await check_security(query):
        return

    if query.data == "data_command":
        await show_page(query, context, page=0)

# === Main ===
app = Application.builder().token(BOT_TOKEN).post_init(send_start_menu).build()

app.add_handler(CommandHandler("data", data_command))
app.add_handler(CallbackQueryHandler(button_handler, pattern=r"^(play|del|page)\|"))
app.add_handler(CallbackQueryHandler(button_handler, pattern=r"^exit$"))
app.add_handler(CallbackQueryHandler(menu_callback, pattern="^data_command$"))

print("✅ DATA Server has started Running...")
write_audit_log(f"✅ DATA Server has started Running...")
app.run_polling()

######################################################################## Camera Script End.


############  PIP Install  ##############
# pip list - Lista na instalirani paketi

# pip install python-telegram-bot==20.3

# pip install opencv-python

# pip install python-dotenv


############ .EXE COMPYLER  Install  ##############
# pip install pyinstaller ttkbootstrap pillow ZA.EXE FILE COMPILER

# python -m pip install --upgrade pip setuptools wheel  ZA.EXE FILE COMPILER

# python -m pip install pyinstaller  ZA.EXE FILE COMPILER

# pyinstaller --noconsole --onefile --windowed --add-data "media;media" --add-data "JSON;JSON" CommandsEditor.py  - CommandsEditor.exe

# pyinstaller --noconsole --onefile --windowed --add-data "media;media" --add-data "JSON;JSON" ScriptsEditor.py  - ScriptsEditor.exe

# pyinstaller --noconsole --onefile Camera.py  - Camera.exe

