#!/usr/bin/env bash
# audio-devices.sh — list outputs (sinks) and microphones (sources) for the Quickshell
# sound panel. One line per device:
#
#   kind|id|default|volume%|muted|type|description
#
#   kind    sink | source
#   default 1 for the current default output / input
#   type    bluetooth | hdmi | usb | headphones | speaker | mic | other
#
# The EQ's own nodes (effect_input/output.qs_eq) and other virtual filter nodes are hidden.

pw-dump 2>/dev/null | jq -r '
	( [ .[] | select(.type == "PipeWire:Interface:Metadata" and .props["metadata.name"] == "default")
	    | .metadata[]? ] ) as $meta
	| ( $meta | map(select(.key == "default.audio.sink"))   | .[0].value.name // "" ) as $dsink
	| ( $meta | map(select(.key == "default.audio.source")) | .[0].value.name // "" ) as $dsrc
	| .[]
	| select(.type == "PipeWire:Interface:Node")
	| .info.props as $p
	| select(($p["media.class"] // "") == "Audio/Sink" or ($p["media.class"] // "") == "Audio/Source")
	| select((($p["node.name"] // "") | test("^effect_|qs_eq|filter-chain")) | not)
	| select(($p["node.link-group"] // "") == "")
	| [ (if $p["media.class"] == "Audio/Sink" then "sink" else "source" end),
	    (.id | tostring),
	    $p["node.name"],
	    ($p["node.description"] // $p["node.nick"] // $p["node.name"]),
	    ($p["device.api"] // ""),
	    ($p["device.form-factor"] // ""),
	    ($p["device.bus"] // ""),
	    (if ($p["media.class"] == "Audio/Sink" and $p["node.name"] == $dsink)
	        or ($p["media.class"] == "Audio/Source" and $p["node.name"] == $dsrc) then "1" else "0" end)
	  ] | join("\u001f")' 2>/dev/null |
while IFS=$'\x1f' read -r kind id name desc api ff bus def; do
	[ -z "$id" ] && continue
	v=$(wpctl get-volume "$id" 2>/dev/null)
	vol=$(echo "$v" | awk '{printf "%.0f", $2 * 100}')
	muted=0
	echo "$v" | grep -q MUTED && muted=1
	lname=$(echo "$name $desc $ff" | tr '[:upper:]' '[:lower:]')
	type=other
	if [ "$api" = bluez5 ] || [[ "$lname" == *bluez* ]]; then type=bluetooth
	elif [[ "$lname" == *hdmi* || "$lname" == *displayport* ]]; then type=hdmi
	elif [ "$kind" = source ]; then type=mic
	elif [ "$bus" = usb ] || [[ "$lname" == *usb* ]]; then type=usb
	elif [[ "$lname" == *headphone* || "$lname" == *headset* || "$ff" == headphone ]]; then type=headphones
	elif [[ "$lname" == *speaker* || "$lname" == *analog* ]]; then type=speaker
	fi
	desc=${desc//|/ }
	echo "$kind|$id|$def|${vol:-0}|$muted|$type|$desc"
done
exit 0
