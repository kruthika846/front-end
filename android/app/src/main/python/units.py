"""Gauge types, their units, and unit conversion.

Every gauge type has a base unit. Values are converted to the base unit and
then out to the requested unit, so any unit of a type converts to any other.
"""

import re

# Linear units: value_in_base = value * factor
# Temperature is affine, so it is handled separately below.
GAUGE_TYPES = {
    "pressure": {
        "label": "Pressure",
        "base": "kPa",
        "units": {
            "Pa": 0.001,
            "kPa": 1.0,
            "MPa": 1000.0,
            "bar": 100.0,
            "mbar": 0.1,
            "psi": 6.894757,
            "kg/cm2": 98.0665,
            "atm": 101.325,
            "inHg": 3.386389,
            "mmHg": 0.1333224,
            "inH2O": 0.249089,
        },
    },
    "temperature": {
        "label": "Temperature",
        "base": "C",
        "units": {"C": None, "F": None, "K": None},
    },
    "vacuum": {
        "label": "Vacuum",
        "base": "kPa",
        "units": {"kPa": 1.0, "bar": 100.0, "mbar": 0.1, "inHg": 3.386389, "mmHg": 0.1333224, "psi": 6.894757},
    },
    "flow": {
        "label": "Flow",
        "base": "L/min",
        "units": {"L/min": 1.0, "L/h": 1 / 60, "m3/h": 1000 / 60, "GPM": 3.785412},
    },
    "level": {
        "label": "Level",
        "base": "%",
        "units": {"%": 1.0},
    },
    "voltage": {
        "label": "Voltage",
        "base": "V",
        "units": {"mV": 0.001, "V": 1.0, "kV": 1000.0},
    },
    "current": {
        "label": "Current",
        "base": "A",
        "units": {"mA": 0.001, "A": 1.0},
    },
    "speed": {
        "label": "Speed",
        "base": "RPM",
        "units": {"RPM": 1.0, "x1000 RPM": 1000.0},
    },
}

# Common spellings people write on dials / in configs
UNIT_ALIASES = {
    "°c": "C", "degc": "C", "celsius": "C", "c": "C",
    "°f": "F", "degf": "F", "fahrenheit": "F", "f": "F",
    "k": "K", "kelvin": "K",
    "kgf/cm2": "kg/cm2", "kg/cm²": "kg/cm2", "kgf/cm²": "kg/cm2",
    "lpm": "L/min", "l/min": "L/min", "l/h": "L/h", "m³/h": "m3/h", "gpm": "GPM",
    "rpm": "RPM", "percent": "%",
}


def normalize_unit(gauge_type, unit):
    """Return the canonical spelling of `unit` for `gauge_type`, or raise."""
    if gauge_type not in GAUGE_TYPES:
        raise ValueError(f"Unknown gauge type '{gauge_type}'. Known: {', '.join(GAUGE_TYPES)}")
    units = GAUGE_TYPES[gauge_type]["units"]
    if unit in units:
        return unit
    alias = UNIT_ALIASES.get(unit.strip().lower())
    if alias in units:
        return alias
    for u in units:
        if u.lower() == unit.strip().lower():
            return u
    raise ValueError(f"Unit '{unit}' is not valid for a {gauge_type} gauge. Valid: {', '.join(units)}")


def _temp_to_c(value, unit):
    if unit == "C":
        return value
    if unit == "F":
        return (value - 32) * 5 / 9
    return value - 273.15  # K


def _c_to_temp(value, unit):
    if unit == "C":
        return value
    if unit == "F":
        return value * 9 / 5 + 32
    return value + 273.15  # K


def convert(value, gauge_type, from_unit, to_unit):
    from_unit = normalize_unit(gauge_type, from_unit)
    to_unit = normalize_unit(gauge_type, to_unit)
    if gauge_type == "temperature":
        return _c_to_temp(_temp_to_c(value, from_unit), to_unit)
    units = GAUGE_TYPES[gauge_type]["units"]
    return value * units[from_unit] / units[to_unit]


def display_unit(unit):
    """Pretty unit for printing (C -> °C)."""
    return {"C": "°C", "F": "°F", "K": "K", "kg/cm2": "kg/cm²", "m3/h": "m³/h"}.get(unit, unit)


# ------------------------------------------------- units read off a dial ----
# OCR text (lower-case, spaces removed) -> (gauge type, unit, score).
# Score says how sure we are: a lone "c" on a dial might be anything, while
# "psi" is unmistakable.
_DIAL_UNITS = {}


def _add(type_, unit, score, *spellings):
    for s in spellings:
        _DIAL_UNITS[s] = (type_, unit, score)


_add("pressure", "bar", 3, "bar", "bars", "8ar")
_add("pressure", "mbar", 3, "mbar")
_add("pressure", "psi", 3, "psi", "psig", "ps1", "lb/in2", "lbf/in2")
_add("pressure", "kPa", 3, "kpa")
_add("pressure", "MPa", 3, "mpa")
_add("pressure", "MPa", 2, "mp")  # the needle often hides the "a"
_add("pressure", "Pa", 1, "pa")
_add("pressure", "kg/cm2", 3, "kg/cm2", "kgf/cm2", "kg/cm", "kgf/cm", "kgcm2", "kgfcm2", "kg/cm^2", "kgf/cm^2")
_add("pressure", "inHg", 3, "inhg", "in.hg", "\"hg", "inchhg")
_add("pressure", "mmHg", 3, "mmhg")
_add("pressure", "inH2O", 3, "inh2o", "in.h2o", "inwc", "\"wc")
_add("pressure", "atm", 2, "atm")
_add("temperature", "C", 3, "°c", "ºc", "˚c", "oc", "0c", "*c", "℃", "degc", "deg.c", "celsius", "°celsius")
_add("temperature", "F", 3, "°f", "ºf", "˚f", "0f", "*f", "℉", "degf", "deg.f", "fahrenheit")
_add("temperature", "F", 2, "of")
_add("temperature", "C", 1, "c")
_add("temperature", "F", 1, "f")
_add("speed", "RPM", 3, "rpm", "r/min", "rev/min")
_add("voltage", "V", 3, "volts", "volt")
_add("voltage", "kV", 2, "kv")
_add("voltage", "mV", 2, "mv")
_add("voltage", "V", 1, "v")
_add("current", "A", 3, "amps", "amp", "ampere", "amperes")
_add("current", "mA", 2, "ma")
_add("current", "A", 1, "a")
_add("level", "%", 2, "%")
_add("flow", "L/min", 3, "l/min", "lpm", "ltr/min")
_add("flow", "m3/h", 3, "m3/h", "m3/hr")
_add("flow", "GPM", 3, "gpm")

VACUUM_WORDS = ("vacuum", "vac", "vakuum")
# Matched inside OCR text; pieces too, because OCR often splits a word
# across the needle ("THER" + "MOMETER").
TEMPERATURE_WORDS = ("temp", "temperat", "thermo", "therm", "mometer")


# OCR look-alikes: the degree sign is often read as ' ` % * o 0 ...
_DEGREE = re.compile(r"^[°º˚'`%*\"o0]+([cf])$")
# kgf/cm²: "/" read as l, 1, |, i;  "²" read as 2, ?, z, or dropped
_KGCM = re.compile(r"^kgf?[/l1|i]?cm[2?z]?$")
# leading number or multiplier: "10bar", "x100kpa", "x1ookpa"
_LEAD = re.compile(r"^(x[0-9o]+|[-0-9.,]+)")


def units_in_text(text):
    """Find dial units in a piece of OCR text. Returns [(type, unit, score)]."""
    t = (text.lower().replace("²", "2").replace("³", "3").replace(" ", "")
         .replace("×", "x"))
    found = []

    def add(hit):
        if hit not in found:
            found.append(hit)

    # whole token first ("kgf/cm2"), then pieces split on separators ("bar/psi")
    pieces = [t] + [p for p in re.split(r"[/,|()]", t) if p]
    for p in pieces:
        p = p.strip(".:;-_~")
        for cand in (p, _LEAD.sub("", p)):
            if cand in _DIAL_UNITS:
                add(_DIAL_UNITS[cand])
                break
            m = _DEGREE.match(cand)
            if m:
                add(("temperature", m.group(1).upper(), 3))
                break
            if _KGCM.match(cand):
                add(("pressure", "kg/cm2", 3))
                break
    return found
