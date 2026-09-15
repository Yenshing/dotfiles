#!/usr/bin/env python3
"""
CodexBar for Herdr (WSL) - Multi-Agent AI Usage & Quota Monitor (Claude & Antigravity)
Monitors both Anthropic Claude (Claude Code) and Google Antigravity (Agy / Gemini / Claude) quota,
providing 5h tab-bar status, 5h sidebar agent metadata, and a full 5h/7d modal dashboard.
"""

import sys
import os
import json
import time
import re
import urllib.request
import urllib.error
import subprocess
from datetime import datetime, timezone

HERDR_DIR = os.path.expanduser("~/.config/herdr")
CACHE_FILE = os.path.join(HERDR_DIR, "quota_cache_multi.json")
CACHE_TTL_SECONDS = 60

# ANSI color codes
ESC = "\033"
BOLD = f"{ESC}[1m"
RESET = f"{ESC}[0m"
CYAN = f"{ESC}[36m"
GREEN = f"{ESC}[32m"
YELLOW = f"{ESC}[33m"
RED = f"{ESC}[31m"
DIM = f"{ESC}[2m"
MAGENTA = f"{ESC}[35m"
BLUE = f"{ESC}[34m"


def format_duration(seconds: int) -> str:
    if seconds <= 0:
        return "now"
    days = seconds // 86400
    hours = (seconds % 86400) // 3600
    minutes = (seconds % 3600) // 60

    if days > 0:
        return f"{days}d {hours}h"
    elif hours > 0:
        return f"{hours}h {minutes}m"
    else:
        return f"{minutes}m"


def get_progress_bar(percent: int, width: int = 24) -> str:
    percent = max(0, min(100, percent))
    filled = round((percent / 100.0) * width)
    empty = max(0, width - filled)
    return ("█" * filled) + ("░" * empty)


def get_color_for_percent(percent: int) -> str:
    if percent >= 50:
        return GREEN
    elif percent >= 20:
        return YELLOW
    else:
        return RED


def get_claude_quota(cached_profile=None) -> dict:
    cred_path = os.path.expanduser("~/.claude/.credentials.json")
    if not os.path.exists(cred_path):
        return {"error": "Claude credentials.json not found"}

    try:
        with open(cred_path, "r", encoding="utf-8") as f:
            cred = json.load(f)

        oauth = cred.get("claudeAiOauth", {})
        token = oauth.get("accessToken")
        plan = oauth.get("subscriptionType", "unknown")
        if not token:
            return {"error": "No access token in Claude credentials"}

        # 1. Fetch usage
        usage_req = urllib.request.Request(
            "https://api.anthropic.com/api/oauth/usage",
            headers={
                "Authorization": f"Bearer {token}",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "claude-code/2.1.266",
            },
        )
        with urllib.request.urlopen(usage_req, timeout=5) as resp:
            usage_data = json.loads(resp.read().decode("utf-8"))

        now_utc = datetime.now(timezone.utc)

        # 5-hour primary window
        fh = usage_data.get("five_hour") or {}
        fh_util = fh.get("utilization", 0.0) or 0.0
        fh_used = round(fh_util)
        fh_rem = max(0, 100 - fh_used)
        fh_reset_sec = 0
        fh_reset_text = ""
        if fh.get("resets_at"):
            try:
                dt = datetime.fromisoformat(fh["resets_at"].replace("Z", "+00:00"))
                fh_reset_sec = max(0, int((dt - now_utc).total_seconds()))
                fh_reset_text = format_duration(fh_reset_sec)
            except Exception:
                pass

        # 7-day secondary window
        sd = usage_data.get("seven_day") or {}
        sd_util = sd.get("utilization", 0.0) or 0.0
        sd_used = round(sd_util)
        sd_rem = max(0, 100 - sd_used)
        sd_reset_sec = 0
        sd_reset_text = ""
        if sd.get("resets_at"):
            try:
                dt = datetime.fromisoformat(sd["resets_at"].replace("Z", "+00:00"))
                sd_reset_sec = max(0, int((dt - now_utc).total_seconds()))
                sd_reset_text = format_duration(sd_reset_sec)
            except Exception:
                pass

        # Account / Profile info
        email = cached_profile.get("email", "") if cached_profile else ""
        org = cached_profile.get("org", "") if cached_profile else ""
        if not email:
            try:
                prof_req = urllib.request.Request(
                    "https://api.anthropic.com/api/oauth/profile",
                    headers={
                        "Authorization": f"Bearer {token}",
                        "anthropic-beta": "oauth-2025-04-20",
                        "User-Agent": "claude-code/2.1.266",
                    },
                )
                with urllib.request.urlopen(prof_req, timeout=3) as prof_resp:
                    prof_data = json.loads(prof_resp.read().decode("utf-8"))
                    email = prof_data.get("account", {}).get("email", "")
                    org = prof_data.get("organization", {}).get("name", "")
            except Exception:
                pass

        return {
            "email": email,
            "plan": plan,
            "org": org,
            "primary": {
                "used": fh_used,
                "remaining": fh_rem,
                "reset_seconds": fh_reset_sec,
                "reset_text": fh_reset_text,
            },
            "secondary": {
                "used": sd_used,
                "remaining": sd_rem,
                "reset_seconds": sd_reset_sec,
                "reset_text": sd_reset_text,
            },
        }
    except Exception as e:
        return {"error": str(e)}


def parse_agy_cli_usage(output_text: str) -> dict:
    result = {}
    now_utc = datetime.now(timezone.utc)
    for line in output_text.splitlines():
        line = line.strip()
        match = re.match(
            r"^(Gemini Models|Claude and GPT models)\t(Weekly Limit Remaining|Five Hour Limit Remaining)\t(\d+)%\t(.*)$",
            line,
        )
        if match:
            model = match.group(1)
            bucket_type = match.group(2)
            pct = int(match.group(3))
            reset_time_str = match.group(4).strip()

            key = "gemini" if "Gemini" in model else "third_party"
            window = "5h" if "Five Hour" in bucket_type else "weekly"

            if key not in result:
                result[key] = {"name": model, "buckets": {}}

            reset_text = ""
            if reset_time_str:
                try:
                    dt = datetime.fromisoformat(reset_time_str.replace("Z", "+00:00"))
                    sec = max(0, int((dt - now_utc).total_seconds()))
                    reset_text = format_duration(sec)
                except Exception:
                    pass

            result[key]["buckets"][window] = {
                "remaining": pct,
                "reset_text": reset_text,
            }
    return result


def get_agy_quota() -> dict:
    agy_paths = [
        os.path.expanduser("~/.local/bin/agy"),
        "/usr/local/bin/agy",
        "/usr/bin/agy",
    ]
    agy_bin = None
    for p in agy_paths:
        if os.path.exists(p) and os.access(p, os.X_OK):
            agy_bin = p
            break

    if not agy_bin:
        try:
            agy_bin = subprocess.check_output(["which", "agy"], text=True).strip()
        except Exception:
            pass

    if agy_bin:
        try:
            proc = subprocess.run(
                [agy_bin, "--print", "/usage"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=8,
            )
            if proc.returncode == 0 and proc.stdout:
                parsed = parse_agy_cli_usage(proc.stdout)
                if parsed and "gemini" in parsed:
                    return parsed
        except Exception as e:
            return {"error": f"agy CLI query failed: {e}"}

    return {"error": "Antigravity service not reachable"}


def get_all_quotas(bypass_cache: bool = False) -> dict:
    cached = None
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                cached = json.load(f)
        except Exception:
            cached = None

    if not bypass_cache and cached:
        try:
            ts = datetime.fromisoformat(cached["timestamp"])
            age = (datetime.now(timezone.utc) - ts).total_seconds()
            if (
                age < CACHE_TTL_SECONDS
                and cached.get("claude")
                and cached.get("agy")
                and "error" not in cached.get("claude", {})
                and "error" not in cached.get("agy", {})
            ):
                return {"claude": cached["claude"], "agy": cached["agy"]}
        except Exception:
            pass

    cached_profile = {}
    if cached and cached.get("claude") and "error" not in cached["claude"]:
        cached_profile = {
            "email": cached["claude"].get("email", ""),
            "org": cached["claude"].get("org", ""),
        }

    claude = get_claude_quota(cached_profile)
    if "error" in claude and cached and cached.get("claude") and "error" not in cached["claude"]:
        claude = cached["claude"]

    agy = get_agy_quota()
    if "error" in agy and cached and cached.get("agy") and "error" not in cached["agy"]:
        agy = cached["agy"]

    data = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "claude": claude,
        "agy": agy,
    }

    try:
        os.makedirs(HERDR_DIR, exist_ok=True)
        tmp_file = CACHE_FILE + f".tmp.{os.getpid()}"
        with open(tmp_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp_file, CACHE_FILE)
    except Exception:
        pass

    return {"claude": claude, "agy": agy}


def get_bucket_val(group_obj, bucket_name: str):
    if not group_obj or not isinstance(group_obj, dict):
        return None
    buckets = group_obj.get("buckets", {})
    return buckets.get(bucket_name)


def update_herdr_panes(quotas: dict):
    try:
        proc = subprocess.run(
            ["herdr", "pane", "list"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=3,
        )
        if proc.returncode != 0 or not proc.stdout:
            return
        panes_obj = json.loads(proc.stdout)
        panes = panes_obj.get("result", {}).get("panes", [])
    except Exception:
        return

    claude = quotas.get("claude", {})
    agy = quotas.get("agy", {})

    g5h = get_bucket_val(agy.get("gemini"), "5h")

    for pane in panes:
        pane_id = pane.get("pane_id")
        if not pane_id:
            continue
        agent = str(pane.get("agent") or "").lower()

        val = ""
        if agent in ["claude", "anthropic"]:
            if "error" not in claude:
                primary = claude.get("primary", {})
                rem = primary.get("remaining", 0)
                reset_t = f" ({primary.get('reset_text')})" if primary.get("reset_text") else ""
                val = f"5h {rem}%{reset_t}"
        elif agent in ["agy", "antigravity"]:
            if "error" not in agy and g5h:
                rem = g5h.get("remaining", 0)
                reset_t = f" ({g5h.get('reset_text')})" if g5h.get("reset_text") else ""
                val = f"5h {rem}%{reset_t}"
        else:
            c_val = f"{claude.get('primary', {}).get('remaining', 0)}%" if "error" not in claude else "N/A"
            g_val = f"{g5h.get('remaining', 0)}%" if g5h else "N/A"
            val = f"Claude 5h {c_val} | Agy 5h {g_val}"

        if val:
            try:
                subprocess.run(
                    [
                        "herdr",
                        "pane",
                        "report-metadata",
                        pane_id,
                        "--source",
                        "codexbar",
                        "--token",
                        f"quota={val}",
                    ],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=2,
                )
            except Exception:
                pass


def run_status(quotas: dict):
    update_herdr_panes(quotas)

    focused_agent = ""
    try:
        proc = subprocess.run(
            ["herdr", "pane", "list"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=3,
        )
        if proc.returncode == 0 and proc.stdout:
            panes_obj = json.loads(proc.stdout)
            for p in panes_obj.get("result", {}).get("panes", []):
                if p.get("focused"):
                    focused_agent = str(p.get("agent") or "").lower()
                    break
    except Exception:
        pass

    claude = quotas.get("claude", {})
    agy = quotas.get("agy", {})

    c_primary = claude.get("primary", {}) if "error" not in claude else {}
    c5h = f"{c_primary.get('remaining')}%" if c_primary else "N/A"
    c_reset = f" ({c_primary.get('reset_text')})" if c_primary.get("reset_text") else ""

    g5h_b = get_bucket_val(agy.get("gemini"), "5h")
    g5h = f"{g5h_b.get('remaining')}%" if g5h_b else "N/A"
    g_reset = f" ({g5h_b.get('reset_text')})" if g5h_b and g5h_b.get("reset_text") else ""

    if focused_agent in ["agy", "antigravity"]:
        print(f"Agy 5h: {g5h}{g_reset}  (Claude 5h: {c5h})")
    elif focused_agent in ["claude", "anthropic"]:
        print(f"Claude 5h: {c5h}{c_reset}  (Agy 5h: {g5h})")
    else:
        print(f"Claude 5h: {c5h}  |  Agy 5h: {g5h}")


def run_dashboard(quotas: dict):
    claude = quotas.get("claude", {})
    agy = quotas.get("agy", {})

    g5h_b = get_bucket_val(agy.get("gemini"), "5h")
    g_wk_b = get_bucket_val(agy.get("gemini"), "weekly")
    tp5h_b = get_bucket_val(agy.get("third_party"), "5h")
    tp_wk_b = get_bucket_val(agy.get("third_party"), "weekly")

    # Clear terminal
    sys.stdout.write(f"{ESC}[2J{ESC}[H")
    sys.stdout.flush()

    print()
    print(f"{CYAN}{BOLD}  +-------------------------------------------------------------------+{RESET}")
    print(f"{CYAN}{BOLD}  |                 CODEXBAR * AI USAGE MONITOR                       |{RESET}")
    print(f"{CYAN}{BOLD}  +-------------------------------------------------------------------+{RESET}")
    print()

    # === SECTION 1: ANTHROPIC CLAUDE ===
    print(f"  {BLUE}{BOLD}[1] Anthropic Claude (Claude Code){RESET}")
    if "error" in claude:
        print(f"     {RED}Error: {claude['error']}{RESET}")
    else:
        email = claude.get("email", "")
        plan = claude.get("plan", "").upper()
        org = claude.get("org", "")
        info_parts = []
        if email:
            info_parts.append(f"Account: {email}")
        if plan:
            info_parts.append(f"({plan} plan)")
        if org:
            info_parts.append(f"Org: {org}")
        if info_parts:
            print(f"     {DIM}{' '.join(info_parts)}{RESET}")

        cp = claude.get("primary", {})
        cs = claude.get("secondary", {})
        cp_rem = cp.get("remaining", 0)
        cs_rem = cs.get("remaining", 0)

        cp_color = get_color_for_percent(cp_rem)
        cs_color = get_color_for_percent(cs_rem)

        print(f"     {BOLD}5-Hour Session Limit:{RESET}")
        print(f"     {cp_color}[{get_progress_bar(cp_rem, 24)}]{RESET} {BOLD}{cp_rem}%{RESET} remaining (resets in {cp.get('reset_text', 'now')})")
        print(f"     {BOLD}7-Day Weekly Limit:{RESET}")
        print(f"     {cs_color}[{get_progress_bar(cs_rem, 24)}]{RESET} {BOLD}{cs_rem}%{RESET} remaining (resets in {cs.get('reset_text', 'now')})")

    print()
    # === SECTION 2: ANTIGRAVITY (AGY) ===
    print(f"  {MAGENTA}{BOLD}[2] Google Antigravity (Agy){RESET}")
    if "error" in agy:
        print(f"     {RED}Error: {agy['error']}{RESET}")
    else:
        g5h = g5h_b.get("remaining", 0) if g5h_b else 0
        gwk = g_wk_b.get("remaining", 0) if g_wk_b else 0
        tp5h = tp5h_b.get("remaining", 0) if tp5h_b else 0
        tpwk = tp_wk_b.get("remaining", 0) if tp_wk_b else 0

        g_color = get_color_for_percent(g5h)
        tp_color = get_color_for_percent(tp5h)

        g_reset_t = g5h_b.get("reset_text", "now") if g5h_b else ""
        g_wk_reset_t = g_wk_b.get("reset_text", "now") if g_wk_b else ""
        tp_reset_t = tp5h_b.get("reset_text", "now") if tp5h_b else ""
        tp_wk_reset_t = tp_wk_b.get("reset_text", "now") if tp_wk_b else ""

        print(f"     {BOLD}Gemini Models (Flash, Pro):{RESET}")
        print(f"     {g_color}[{get_progress_bar(g5h, 24)}]{RESET} {BOLD}{g5h}%{RESET} remaining (5h reset: {g_reset_t})")
        print(f"     {DIM}Weekly limit: {gwk}% remaining (resets in: {g_wk_reset_t}){RESET}")
        print()
        print(f"     {BOLD}Claude & GPT Models (Sonnet, Opus, GPT):{RESET}")
        print(f"     {tp_color}[{get_progress_bar(tp5h, 24)}]{RESET} {BOLD}{tp5h}%{RESET} remaining (5h reset: {tp_reset_t})")
        print(f"     {DIM}Weekly limit: {tpwk}% remaining (resets in: {tp_wk_reset_t}){RESET}")

    print()
    # === SECTION 3: HERDR PANES ===
    try:
        proc = subprocess.run(
            ["herdr", "pane", "list"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=2,
        )
        if proc.returncode == 0 and proc.stdout:
            panes_obj = json.loads(proc.stdout)
            panes = panes_obj.get("result", {}).get("panes", [])
            print(f"  {DIM}{BOLD}Active Herdr Panes & Agents:{RESET}")
            for p in panes:
                agent_name = p.get("agent") or "shell"
                st = p.get("agent_status", "")
                st_color = GREEN if st == "working" else (RED if st == "blocked" else DIM)
                st_text = f"{st_color}{st}{RESET}" if st else "active"
                focus_mark = f"{CYAN}* {RESET}" if p.get("focused") else "  "
                tokens = p.get("tokens") or {}
                t_quota = f" | Quota: {tokens.get('quota')}" if tokens.get("quota") else ""
                print(f"    {focus_mark}[{p.get('pane_id')}] {BOLD}{agent_name}{RESET} ({p.get('workspace_id')}/{p.get('tab_id')}) - {st_text}{DIM}{t_quota}{RESET}")
    except Exception:
        pass

    print()
    print(f"{DIM}  ---------------------------------------------------------------------{RESET}")
    print(f"{DIM}  Press Enter, Esc or q to close...{RESET}")

    # Wait for keypress
    try:
        import termios
        import tty

        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    except Exception:
        try:
            input()
        except Exception:
            pass


def print_help():
    print("CodexBar for Herdr (WSL) - Multi-Agent AI Quota Monitor")
    print()
    print("Usage:")
    print("  codexbar                 Display current usage for both Claude and Agy")
    print("  codexbar agy             Display only Antigravity (Gemini / Claude / GPT) usage")
    print("  codexbar claude          Display only Anthropic Claude usage")
    print("  codexbar dash            Open the full interactive ASCII dashboard")
    print("  codexbar status          Print single-line 5h status for Herdr tab bar")
    print("  codexbar update          Update Herdr sidebar metadata for all agent panes")
    print("  codexbar refresh         Force refresh cache from APIs and print")
    print("  codexbar json            Output raw quota data as JSON")


def main():
    target = sys.argv[1].lower() if len(sys.argv) > 1 else ""

    if target in ["help", "-h", "--help"]:
        print_help()
        sys.exit(0)

    bypass_cache = target in ["refresh", "reload", "--refresh"]
    quotas = get_all_quotas(bypass_cache=bypass_cache)

    if target in ["json", "--json"]:
        print(json.dumps(quotas, indent=2))
        sys.exit(0)

    if target in ["update", "update-panes", "--update"]:
        update_herdr_panes(quotas)
        print("Herdr panes metadata updated with 5h quota.")
        sys.exit(0)

    if target in ["status", "status-bar", "statusbar", "--status"]:
        run_status(quotas)
        sys.exit(0)

    if target in ["dash", "dashboard", "--dashboard"]:
        run_dashboard(quotas)
        sys.exit(0)

    # Standard CLI display
    show_claude = target not in ["agy", "antigravity"]
    show_agy = target not in ["claude", "anthropic"]

    print(f"{CYAN}{BOLD}==> CodexBar: AI Usage & Quota Monitor (WSL){RESET}")
    print()

    claude = quotas.get("claude", {})
    agy = quotas.get("agy", {})

    if show_claude:
        print(f"{BLUE}{BOLD}[Anthropic Claude]{RESET}")
        if "error" in claude:
            print(f"  Error: {claude['error']}")
        else:
            email = claude.get("email", "")
            plan = claude.get("plan", "").upper()
            org = claude.get("org", "")
            header = []
            if email:
                header.append(f"Account: {email}")
            if plan:
                header.append(f"({plan} plan)")
            if org:
                header.append(f"| Org: {org}")
            if header:
                print(f"  {DIM}{' '.join(header)}{RESET}")

            cp = claude.get("primary", {})
            cs = claude.get("secondary", {})
            cp_rem = cp.get("remaining", 0)
            cs_rem = cs.get("remaining", 0)
            cp_col = get_color_for_percent(cp_rem)
            cs_col = get_color_for_percent(cs_rem)

            print(f"  Session 5h: {cp_col}{cp_rem}%{RESET} (resets in {cp.get('reset_text', 'now')})")
            print(f"  Weekly 7d:  {cs_col}{cs_rem}%{RESET} (resets in {cs.get('reset_text', 'now')})")

    if show_claude and show_agy:
        print()

    if show_agy:
        print(f"{MAGENTA}{BOLD}[Antigravity / Agy]{RESET}")
        if "error" in agy:
            print(f"  Error: {agy['error']}")
        else:
            g5h_b = get_bucket_val(agy.get("gemini"), "5h")
            g_wk_b = get_bucket_val(agy.get("gemini"), "weekly")
            tp5h_b = get_bucket_val(agy.get("third_party"), "5h")
            tp_wk_b = get_bucket_val(agy.get("third_party"), "weekly")

            g5h = g5h_b.get("remaining", 0) if g5h_b else 0
            gwk = g_wk_b.get("remaining", 0) if g_wk_b else 0
            tp5h = tp5h_b.get("remaining", 0) if tp5h_b else 0
            tpwk = tp_wk_b.get("remaining", 0) if tp_wk_b else 0

            g_col = get_color_for_percent(g5h)
            tp_col = get_color_for_percent(tp5h)

            g_reset_t = g5h_b.get("reset_text", "now") if g5h_b else ""
            tp_reset_t = tp5h_b.get("reset_text", "now") if tp5h_b else ""

            print(f"  Gemini Models:     5h {g_col}{g5h}%{RESET} (resets in {g_reset_t}) | Weekly: {gwk}%")
            print(f"  Claude/GPT Models: 5h {tp_col}{tp5h}%{RESET} (resets in {tp_reset_t}) | Weekly: {tpwk}%")


if __name__ == "__main__":
    main()
