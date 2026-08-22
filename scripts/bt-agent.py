#!/usr/bin/env python3
# Bluetooth pairing agent for Quickshell control center.
# Registers a KeyboardDisplay agent and communicates PIN/passkey/confirm
# requests via files in /tmp.
#
# Request file:  /tmp/quickshell-bt-req.txt
# Response file: /tmp/quickshell-bt-resp.txt
#
# Request format:
#   PINCODE <device_path> <address> <name>
#   PASSKEY <device_path> <address> <name>
#   CONFIRM <device_path> <address> <name> <passkey>
#   AUTHORIZE <device_path> <address> <name>
#   AUTHORIZE_SERVICE <device_path> <address> <name> <uuid>
#
# Response format:
#   <device_path> <value>
#   where value is PIN for PINCODE, number for PASSKEY, yes/no for CONFIRM/AUTHORIZE.

import sys
import os
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

AGENT_PATH = "/quickshell/btagent"
AGENT_CAPABILITY = "KeyboardDisplay"
REQ_FILE = "/tmp/quickshell-bt-req.txt"
RESP_FILE = "/tmp/quickshell-bt-resp.txt"

pending = {}


def eprint(msg):
    print(msg, file=sys.stderr, flush=True)


def get_device_info(bus, device_path):
    try:
        dev = bus.get_object("org.bluez", device_path)
        props = dbus.Interface(dev, "org.freedesktop.DBus.Properties")
        name = props.Get("org.bluez.Device1", "Name")
        addr = props.Get("org.bluez.Device1", "Address")
        return str(name), str(addr)
    except Exception as e:
        eprint(f"get_device_info error: {e}")
        return "Unknown", "00:00:00:00:00:00"


def clear_request_file():
    try:
        with open(REQ_FILE, "w") as f:
            f.write("")
    except Exception:
        pass


def send_request(req):
    try:
        with open(REQ_FILE, "w") as f:
            f.write(req + "\n")
    except Exception as e:
        eprint(f"send_request error: {e}")


def read_response(device_path):
    try:
        with open(RESP_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split(" ", 1)
                if parts[0] == device_path:
                    return parts[1] if len(parts) > 1 else None
    except Exception as e:
        eprint(f"read_response error: {e}")
    return None


def clear_response(device_path):
    try:
        lines = []
        with open(RESP_FILE, "r") as f:
            lines = f.readlines()
        with open(RESP_FILE, "w") as f:
            for line in lines:
                if not line.startswith(device_path + " "):
                    f.write(line)
    except Exception:
        pass


def wait_for_response(device_path, timeout=120):
    import time
    end = time.time() + timeout
    while time.time() < end:
        val = read_response(device_path)
        if val is not None:
            clear_response(device_path)
            return val
        time.sleep(0.2)
    return None


class Agent(dbus.service.Object):
    def __init__(self, bus, path):
        dbus.service.Object.__init__(self, bus, path)

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        name, addr = get_device_info(bus, device)
        send_request(f"PINCODE {device} {addr} {name}")
        eprint(f"RequestPinCode {device} {addr} {name}")
        val = wait_for_response(device)
        clear_request_file()
        if val is None:
            raise dbus.DBusException("org.bluez.Error.Canceled")
        return val

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        name, addr = get_device_info(bus, device)
        send_request(f"DISPLAY_PINCODE {device} {addr} {name} {pincode}")

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        name, addr = get_device_info(bus, device)
        send_request(f"PASSKEY {device} {addr} {name}")
        eprint(f"RequestPasskey {device} {addr} {name}")
        val = wait_for_response(device)
        clear_request_file()
        if val is None:
            raise dbus.DBusException("org.bluez.Error.Canceled")
        return dbus.UInt32(int(val))

    @dbus.service.method("org.bluez.Agent1", in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        name, addr = get_device_info(bus, device)
        send_request(f"DISPLAY_PASSKEY {device} {addr} {name} {passkey} {entered}")

    @dbus.service.method("org.bluez.Agent1", in_signature="ou", out_signature="")
    def RequestConfirmation(self, device, passkey):
        name, addr = get_device_info(bus, device)
        send_request(f"CONFIRM {device} {addr} {name} {passkey}")
        eprint(f"RequestConfirmation {device} {addr} {name} {passkey}")
        val = wait_for_response(device)
        clear_request_file()
        if val != "yes":
            raise dbus.DBusException("org.bluez.Error.Rejected")

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        name, addr = get_device_info(bus, device)
        send_request(f"AUTHORIZE {device} {addr} {name}")
        val = wait_for_response(device)
        clear_request_file()
        if val != "yes":
            raise dbus.DBusException("org.bluez.Error.Rejected")

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        name, addr = get_device_info(bus, device)
        send_request(f"AUTHORIZE_SERVICE {device} {addr} {name} {uuid}")
        val = wait_for_response(device)
        clear_request_file()
        if val != "yes":
            raise dbus.DBusException("org.bluez.Error.Rejected")

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Cancel(self):
        clear_request_file()
        for dev in list(pending.keys()):
            pending.pop(dev, None)

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Release(self):
        sys.exit(0)


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    global bus
    bus = dbus.SystemBus()
    agent = Agent(bus, AGENT_PATH)

    manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"),
                             "org.bluez.AgentManager1")
    try:
        manager.RegisterAgent(AGENT_PATH, AGENT_CAPABILITY)
        manager.RequestDefaultAgent(AGENT_PATH)
    except Exception as e:
        eprint(f"Agent already registered or error: {e}")
        sys.exit(0)

    clear_request_file()
    open(RESP_FILE, "a").close()

    mainloop = GLib.MainLoop()
    mainloop.run()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        eprint(f"Fatal: {e}")
        sys.exit(1)
