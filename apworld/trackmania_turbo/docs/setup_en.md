# Trackmania Turbo Setup Guide

## Required software

- Trackmania Turbo (Steam/Epic/Uplay)
- [Openplanet for Trackmania Turbo](https://openplanet.dev/)
- The Archipelago plugin for Trackmania Turbo (`Archipelago.op`, from the
  [GitHub Releases page](https://github.com/Sigeth/tmturbo-ap/releases))

## Installing the plugin

Drop `Archipelago.op` into `%USERPROFILE%\OpenplanetTurbo\Plugins\`, then enable
it from the Openplanet menu. (For development, symlink the repo instead:
`cmd /c mklink /D "%USERPROFILE%\OpenplanetTurbo\Plugins\Archipelago" "<repo>"`.)

## Connecting

1. Open the **Archipelago** window from the Openplanet menu.
2. Enter the server host, port and your slot name.
3. Untick **Use TLS** for a local server; leave it ticked for `archipelago.gg`.
4. Click **Connect**.

## What gets checked

Earning a Gold or Author medal on an official campaign track sends a location
check, and so does finishing every track of a block ("<Tier> <Env> Complete") or
a whole tier ("<Tier> Complete"). Set `medals_required` lower (`silver` /
`bronze`) to make those tiers checkable too, or `author` for Author only.

## How the campaign unlocks

The 200 tracks are 20 blocks of 10. The multiworld hands you `Progressive
Medal` items — one currency for the whole campaign — and a block opens once
you hold `10 x <block number>` of them (block 1 needs 10, block 19 needs 190).
Once a block is open, finishing a track sends whatever medal you earned. The
plugin enforces the locks because Turbo exposes no unlock API. The goal is to
finish (any medal, or none) all 200 tracks.

(A future `unlock_style: real_medals` option is reserved for gating each block
on the exact Bronze/Silver/Gold grade it needs, but isn't implemented yet.)
