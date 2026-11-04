# งานสำหรับ Kiro: รถโชว์บนแท่นหมุน + สนามแข่งส่วนตัว (2 ส่วน)

## บริบท
- โปรเจกต์ Roblox (Rojo + Luau `--!strict`) เกม garage tycoon มี "ห้อง Tuning" (unlock `TuningRoom`) อยู่หลังอาคาร มีแท่นหมุนกับคอมพิวเตอร์แต่งรถ
- งานรอบนี้มี 2 ส่วน **ทำส่วน A ให้เสร็จและทดสอบก่อน แล้วค่อยทำส่วน B**
  - **A — รถโชว์:** เอารถที่ผู้เล่นเลือกไว้ (`selectedCar`) มาโชว์บนแท่นหมุน
  - **B — สนามแข่งส่วนตัว:** unlock ใหม่ `RaceTrack` ราคา $150,000 อยู่หลังห้อง Tuning จับเวลาต่อรอบ **ไม่มีรางวัลเงิน** เข้าสนามผ่านปุ่มในเมนู Tuning
- อ่านก่อนเริ่ม: `docs/CONTRACT.md`, `docs/KIRO_NPC_PROMPT.md` (กติกาเดิม)
- ไฟล์หลักที่เกี่ยวข้อง:
  - `src/shared/Layout.luau` (`ANNEX`, `TUNING`, `DRIVE_SPAWN`)
  - `src/shared/Config/Unlocks.luau`
  - `src/server/Services/MapBuilder.luau` (`buildTuningRoom` ~บรรทัด 1877, `buildUnlockables` ~1993, `buttonPosition` ~2029)
  - `src/server/Services/UnlockService.luau` (`buttonPosition` ~167, `nextUnlock` ~117, `allOwned` ~134, `refreshButtons` ~204)
  - `src/server/Services/PersonalCarService.luau` (`driveCar` ~196, `returnCar` ~245, `despawn` ~186, `guarded` ~77)
  - `src/server/Services/RebirthService.luau`, `src/server/Services/PlayerData.luau`
  - `src/client/Controllers/Tuning.luau` (ปุ่ม `driveBtn` ~บรรทัด 455 และ handler ~1590, `open`/`close`)
  - `src/client/Controllers/DriveHUD.luau`
  - Strings: `src/shared/Config/Strings.luau` (notify_*, unlock_*), `StringsUI.luau` (drive_*), `StringsTuning.luau` (tuning_*)

## กติกาที่ต้องทำตาม
1. **ใช้เฉพาะ Enum/property/API ที่มีจริงใน Roblox** ถ้าไม่แน่ใจให้ตรวจเอกสารก่อน (เคยพังเพราะ `Material.Rust`)
2. `--!strict` ต้องไม่มี type error สไตล์เหมือนไฟล์เดิม (tab, คอมเมนต์ภาษาอังกฤษสั้น ๆ)
3. **ห้ามเพิ่ม RemoteEvent/RemoteFunction ใหม่** ใช้ของเดิมใน `src/shared/Remotes.luau` (รายละเอียดอยู่ในแต่ละข้อ)
4. ทุก Strings key ที่เพิ่มต้องมีทั้ง `th` และ `en` (ชุด key สองภาษาต้องเท่ากัน)
5. ห้าม `math.clamp(x, min, max)` ที่ min อาจมากกว่า max (เคยทำให้รถหายมาแล้ว)
6. ห้ามแตะ `GarageTycoon.rbxlx`, ห้าม `git commit`, ห้ามแก้ไฟล์ที่ไม่เกี่ยว, ห้ามเปลี่ยน `STARTING_MONEY`
7. ห้ามสร้าง loop ต่อรถ/ต่อผู้เล่นแบบ `while true` ใช้ `RunService.Heartbeat` ตัวเดียวต่อ service
8. ทุกอย่างที่สร้างต้องถูกเก็บกวาดเมื่อผู้เล่นออก/รถถูก despawn/plot ถูกปล่อย (`PlotService.onReleased`)
9. Service ใหม่ฝั่ง server ต้องเพิ่มชื่อใน `ORDER` ของ `src/server/Main.server.luau` (หลัง `PersonalCarService`) ส่วน controller ฝั่ง client ใส่ใน `src/client/Controllers/` แล้วจะถูกโหลดอัตโนมัติ (ต้องมี `start()`)

---

## ส่วน A — รถโชว์บนแท่นหมุน

### เป้าหมาย
เมื่อผู้เล่นมีรถและห้อง Tuning ให้รถคัน `selectedCar` (แต่งตามชิ้นส่วนที่ติดตั้งจริง `data.cars[id].custom`) ตั้งอยู่บนแท่นหมุนและหมุนช้า ๆ ใครเดินเข้ามาในห้องก็เห็น

### Server (`src/server/Services/ShowcaseService.luau` ใหม่ หรือใส่ใน `PersonalCarService` ถ้าเล็กพอ)
- สร้างด้วย `CarBuilder.buildCustom(carId, save.custom)` ตั้งชื่อ model `"ShowcaseCar"`
  - ตำแหน่ง: `Layout.toWorld(plotIndex, Layout.TUNING.turntable) * CFrame.new(0, 0.6, 0)` (ผิวบนแท่นอยู่ที่ Y 0.6 ใช้ค่าเดียวกับ `Tuning.luau` `turntableBase`)
  - ใส่ไว้ในโฟลเดอร์ของห้อง Tuning ในแปลง (`plot.Unlockables.TuningRoom`) เพื่อให้ถูกซ่อนไปพร้อมห้องตอนยังไม่ได้ซื้อ/หลัง rebirth หรือโฟลเดอร์แยกที่จัดการเองก็ได้ แต่ต้องหายเมื่อห้องหาย
  - ให้รถ Anchored ทั้งคัน (Root ของ CarBuilder Anchored อยู่แล้ว ชิ้นอื่นเชื่อมด้วย WeldConstraint) ห้ามให้ชนผู้เล่น/ห้ามมีฟิสิกส์
  - ใส่ attribute `ShowcaseOwner = player.UserId` บน model
- **สร้างใหม่เมื่อ:** ได้ plot (`PlotService.onAssigned`), ซื้อ `TuningRoom` (`UnlockService.onUnlocked`), เปลี่ยน `selectedCar`, ซื้อ/ติดตั้งชิ้นส่วน (`Customize`), ซื้อรถ (`BuyCar`)
  - แนะนำ: ตรวจ "ลายเซ็น" (`selectedCar` + JSON ของ `custom`) จาก `PlayerData` หลัง update แล้วสร้างใหม่เฉพาะตอนเปลี่ยน ไม่ใช่ทุก snapshot (snapshot ถูกส่งทุกครั้งที่เงินเข้า)
  - `PlayerData` **ไม่มี** hook หลัง `update` (มีแค่ `update`, `push`, `addSnapshotField`) ให้เรียกฟังก์ชัน refresh จาก `buyCar/selectCar/customize` ใน `PersonalCarService` โดยตรงหลัง `PlayerData.update`
- **ตอนขับ:** `driveCar` → ลบรถโชว์, `despawn` → สร้างกลับ
- **rebirth / ปล่อย plot / ผู้เล่นออก:** ลบรถโชว์
- ถ้า `buildCustom` error ต้อง `pcall` ไว้ และไม่ลบรถคันเดิมก่อนสร้างคันใหม่สำเร็จ (บั๊กเดิมของเมนู Tuning)

### Client (`src/client/Controllers/Showcase.luau` ใหม่)
- หมุนรถโชว์ทุกคันใน workspace ที่ชื่อ `ShowcaseCar` รอบแกน Y ช้า ๆ (~12°/วินาที) ด้วย `PivotTo` ฝั่ง client (แค่ภาพ ไม่ต้องส่ง server) เก็บมุมเริ่มต้นจาก pivot ที่ server วาง
- **ตอนเปิดเมนู Tuning ต้องซ่อนรถโชว์ของตัวเอง** (เมนูมีรถพรีวิวของมันวางที่จุดเดียวกัน) แล้วแสดงกลับตอนปิด
  - วิธีที่แนะนำ: `Tuning.luau` ตั้ง attribute บน `LocalPlayer` เช่น `TuningOpen = true/false` ใน `open()`/`close()` แล้ว Showcase controller ฟัง attribute นี้ ซ่อนด้วย `LocalTransparencyModifier = 1` ของทุก BasePart ในรถโชว์ที่ `ShowcaseOwner == LocalPlayer.UserId`
  - รถโชว์ถูก server สร้างใหม่ระหว่างเมนูเปิดอยู่ได้ ต้องซ่อนคันใหม่ด้วย (ฟัง `DescendantAdded`/`ChildAdded`)

### เกณฑ์ผ่านส่วน A
- เข้าเกมที่มีรถแล้ว เห็นรถคันที่เลือกบนแท่น หมุนช้า ๆ สีและชิ้นส่วนตรงกับที่ติดตั้ง
- เปลี่ยนคัน/ติดตั้งชิ้นส่วนในเมนู → ปิดเมนูแล้วรถโชว์เป็นแบบใหม่
- เปิดเมนู → ไม่มีรถสองคันซ้อนกัน
- กด DRIVE → รถบนแท่นหาย, กด Return → กลับมา
- ไม่มี error ใน Output (ลองรถทั้ง 6 คัน รวม Super + ฝากระโปรง Carbon)

---

## ส่วน B — สนามแข่งส่วนตัว

### B.1 Config และ Layout
- `src/shared/Config/Unlocks.luau` เพิ่มท้ายรายการ:
  `{ id = "RaceTrack", price = 150000, kind = "RaceTrack", anytime = true, requires = "TuningRoom", keepOnRebirth = true }`
  - `requires`: ปุ่มซื้อจะแสดงก็ต่อเมื่อมี `TuningRoom` แล้ว (ปุ่มอยู่ในห้อง Tuning) แก้ `refreshButtons` ใน `UnlockService` ให้เคารพ `requires` และ `tryPurchase` ต้องปฏิเสธถ้ายังไม่มี requires
  - `keepOnRebirth`: สนามเป็นของส่วนตัวแบบเดียวกับรถ **ไม่ต้องรีเซ็ตตอน rebirth** และ **ไม่ใช่เงื่อนไขของ rebirth**
    - `UnlockService.nextUnlock`/`allOwned` ต้องข้าม entry ที่ `keepOnRebirth = true` (ไม่ถูก suggest ด้วยลูกศรนำทางและไม่บังคับให้ซื้อก่อน rebirth)
    - `RebirthService`: ตอนรีเซ็ต `d.unlocks = {}` ให้คง unlock ที่ `keepOnRebirth` ไว้
    - หลัง rebirth ห้อง Tuning หายแต่สนามยังเป็นของผู้เล่น: ตัวสนามยังแสดงได้ (มันอยู่นอกห้อง) แต่เข้าไปขับผ่านเมนูได้ก็ต่อเมื่อซื้อห้อง Tuning คืน ซึ่งเป็นพฤติกรรมที่ยอมรับได้
- `src/shared/Layout.luau` เพิ่ม `Layout.TRACK` (พิกัด local ของ plot เหมือนค่าอื่น: -Z = ด้านหน้าแปลงฝั่งวงเวียน, ห้อง Tuning อยู่ Z 60–104, กำแพงหลังห้องคือ Z 103.5–104)
  - `button = Vector3.new(0, 0, 99)` ปุ่มซื้อบนพื้นห้อง Tuning ชิดกำแพงหลังใต้ป้าย TUNE YOUR RIDE (ปุ่มขนาด 8×8 → Z 95–103 ส่วนแท่นหมุน + วงแหวนนีออนกินถึง Z ~93.9 และผิวในกำแพงหลังอยู่ที่ Z 103 จึงพอดีไม่ทับ)
  - `door = { x = 0, halfWidth = 8, z = 104 }` ประตูที่กำแพงหลังห้อง Tuning
  - `bounds = { minX = -140, maxX = 140, minZ = 110, maxZ = 390 }` พื้นที่สนามทั้งหมดต้องอยู่ในนี้ (ตรวจแล้วว่าไม่ชนแปลงข้าง ๆ และอยู่ในพื้น Ground ขนาด 1400×1400)
  - `width = 28` ความกว้างถนน
  - `path = { ... }` เส้นกึ่งกลางถนนเป็น **วงปิด** รายการ `Vector3` (Y = 0) เรียงตามทิศวิ่ง จุดแรกคือเส้นสตาร์ท
  - `start = CFrame` ตำแหน่ง/ทิศเกิดรถ ห่างหลังเส้นสตาร์ท ~20 studs หันไปตามทิศวิ่ง (`CFrame.lookAt`)
  - `checkpoints = { number }` index ของจุดใน `path` ที่เป็น checkpoint 8 จุดกระจายเท่า ๆ กันตามความยาว (ไม่รวมเส้นสตาร์ทที่ index 1)

### B.2 รูปทรงสนาม (ออกแบบเอง แต่ต้องตามข้อจำกัดนี้)
- ความยาวรอบ **900–1300 studs** (รถเร็วสุด Super อัปเกรดเต็ม ~165 studs/s → ~8–15 วินาทีต่อรอบ สนามเล็กเกินจะไม่สนุก)
- มีทางตรงยาว ≥ 1 ช่วง (≥ 200 studs) สำหรับเร่ง, โค้งหักศอก (hairpin) 1 จุด, S-bend 1 จุด
- รัศมีโค้งต่ำสุด **≥ 30 studs** (ที่กึ่งกลางถนน) ถนนต้องไม่ตัด/ทับตัวเอง และขอบนอกถนนทุกจุดอยู่ใน `bounds`
- จุดใน `path` บนโค้งห่างกัน ≤ 8 studs ทางตรงใช้จุดน้อยได้ (แต่ต้องมีจุดให้ checkpoint)
- **ต้องมีทางเชื่อมเดินเท้า** จากประตูหลังห้อง Tuning (Z 104) ไปถึงขอบสนาม (เป็นทางเดิน ไม่ใช่ถนนรถ)
- แนะนำ: เขียนฟังก์ชันช่วยสร้าง `path` จาก "ทางตรง + arc" (เช่น `arc(center, radius, a0, a1)`) แทนพิมพ์พิกัดด้วยมือ และเขียนคอมเมนต์ความยาวรอบที่คำนวณได้ไว้ใน `Layout.TRACK`

### B.3 สร้างโมเดลสนาม (`MapBuilder`)
- เพิ่ม `kind == "RaceTrack"` ใน `buildUnlockables` → `buildRaceTrack(ctx, folder)` สร้าง Model ชื่อ `"RaceTrack"` (ระบบเดิมจะซ่อน/แสดงตาม unlock ให้อัตโนมัติ ดูว่า `TuningRoom` ทำงานอย่างไรแล้วทำแบบเดียวกัน)
- เพิ่ม `kind == "RaceTrack"` → `Layout.TRACK.button` ใน `buttonPosition` ของ **ทั้ง** `MapBuilder.luau` และ `UnlockService.luau`
- ชิ้นส่วนในสนาม:
  - **ถนน:** ชิ้นต่อชิ้นระหว่างจุดใน `path` ยาวพอให้ซ้อนกันเล็กน้อย (ไม่มีช่องโหว่ที่โค้ง) วัสดุ `Asphalt` หรือ `Concrete` สีเข้ม, CanCollide = true, ด้านบนถนนสูงกว่าพื้นหญ้าเล็กน้อย (~0.1) และ **ต้องเรียบ** ไม่มีขั้นที่ทำให้รถกระเด้ง
  - **Curb:** ขอบโค้งลายแดง/ขาวสลับ บาง ๆ (สูง ≤ 0.3) CanCollide = false หรือแบนพอที่รถไม่สะดุด
  - **เส้นสตาร์ท/ฟินิช:** ลายตารางหมากรุกบนพื้น + ซุ้ม (gantry) คร่อมถนนเขียนคำว่า "START / FINISH" (SurfaceGui เหมือนป้ายอื่นใน MapBuilder)
  - อัฒจันทร์ 1 จุดข้างทางตรง, ธง/ป้ายประดับเล็กน้อย ใช้สี accent ของ plot (`ctx.accent` / `tag(part, "Accent")`) ให้เปลี่ยนตาม theme ได้
  - **ขอบเขตกันตก:** สนามอยู่บนพื้นหญ้าเรียบ ไม่ต้องมีกำแพง แต่ห้ามมีอะไรขวางถนน
  - ประตูในกำแพงหลังห้อง Tuning: ตอนนี้กำแพงหลังเป็นชิ้นเดียว (`AnnexWall` ที่ `A.maxZ - 0.5` ใน `buildTuningRoom`) ให้แยกเป็น 2 ชิ้นซ้าย/ขวา + คานบน เว้นช่องประตู X −8..8 แล้วใส่ "ประตูม้วน" ปิดช่องไว้ (ดูตัวอย่าง `buildAnnexDoor`) **เปิดประตูเมื่อมี `RaceTrack`** (ระบบ `HideWhenOwned` เดิมเก็บเฉพาะชิ้นใน `Static` ถ้าประตูอยู่ใน model TuningRoom ให้ service ฝั่ง track ซ่อน/แสดงเองตอนได้ plot และตอนซื้อ)
  - ระวังโปสเตอร์ "TUNE YOUR RIDE" (x = 0) กับป้าย TUNING ด้านนอก (`AnnexSignBack` x = 0, y = 11) ซ้อนช่องประตู: ย้ายขึ้น/ย้ายข้างให้ไม่ทับประตู (ประตูสูง ~11.5)
- **Performance:** จำนวน Part ของสนามทั้งหมด **≤ 600** ใช้ชิ้นยาวสำหรับทางตรง ห้าม `Union`/mesh

### B.4 เข้าสนาม (`PersonalCarService` + `Tuning.luau`)
- ขยาย remote `DriveCar` เดิมเป็น `(carId, mode?)` โดย `mode` เป็น `"track"` หรือ nil (nil = พฤติกรรมเดิมทุกอย่าง) อัปเดตคอมเมนต์ใน `Remotes.luau` และ `docs/CONTRACT.md`
  - `mode == "track"` ต้องตรวจ server-side ว่ามี `RaceTrack` (ถ้าไม่มี → `notify_need_track`, return false)
  - วางรถที่ `Layout.toWorld(plotIndex, Layout.TRACK.start) * CFrame.new(0, 1, 0)` แทน `DRIVE_SPAWN`
  - ใส่ attribute บนรถ `OnTrack = true`
- `returnCar` เดิมพาผู้เล่นกลับไปที่คอมพิวเตอร์ Tuning อยู่แล้ว ใช้ได้เลย
- `Tuning.luau`: เพิ่มปุ่ม **"ขับในสนาม"** ข้าง/ใต้ปุ่ม DRIVE แสดงเฉพาะเมื่อ snapshot บอกว่ามี `RaceTrack` (snapshot ปัจจุบัน **ไม่ได้ส่ง** `unlocks` ให้ client ให้เพิ่ม `snapshot.hasTrack` ใน `addSnapshotField` เดิมของ `PersonalCarService` ประมาณบรรทัด 348)
  - เงื่อนไขกดได้เหมือน DRIVE ปัจจุบัน: `hasAnyCar() and hasCar(previewCarId) and not busy` และก่อนขับให้ติดตั้งชิ้นส่วนที่พรีวิวไว้และเป็นของผู้เล่นแล้วแบบเดียวกับ handler ของ DRIVE (**แยก logic นี้เป็นฟังก์ชันเดียวแล้วเรียกจากทั้งสองปุ่ม** ห้าม copy)
  - ต้องวางให้พอดีทั้ง desktop และโหมดจอเล็ก (`compactMode` ใน `applyLayout`) ไม่ทับป้ายเงิน/ปุ่มปิด

### B.5 จับเวลา (server เป็นผู้ตัดสิน)
- Service ใหม่ `src/server/Services/RaceTrackService.luau` (เพิ่มใน `ORDER` หลัง `PersonalCarService`)
- Heartbeat ตัวเดียว เช็กรถทุกคันที่มี `OnTrack = true` ไม่ต้องทุกเฟรม (ทุก ~0.05–0.1 วินาทีพอ)
  - ตำแหน่งรถ: pivot ของรถแปลงเป็นพิกัด local ของ plot (`Layout.plotCFrame(plotIndex):PointToObjectSpace(...)`)
  - **ห้ามใช้ `Touched`** (ไม่น่าเชื่อถือที่ความเร็วสูง) ให้ตรวจว่ารถผ่าน "ประตู" ของ checkpoint ด้วยการเช็กว่าเส้นจากตำแหน่งก่อนหน้า → ตำแหน่งปัจจุบันตัดเส้นขวางถนนที่จุดนั้น (เส้นยาว `width + 6` ตั้งฉากกับทิศถนน) เพื่อไม่พลาดตอนวิ่งเร็ว
- กติกา:
  - รอบเริ่มเมื่อรถตัดเส้นสตาร์ทครั้งแรก
  - ต้องผ่าน checkpoint **ตามลำดับครบทุกจุด** แล้วตัดเส้นสตาร์ทอีกครั้ง = จบรอบ
  - ถ้าข้าม checkpoint (เช่นลัดสนาม) รอบนั้นไม่นับ ต้องกลับไปผ่านจุดที่ค้างก่อน
  - รอบที่เร็วกว่า `TRACK_LENGTH / 220` วินาที ถือว่าโกง ไม่นับ (ค่า 220 studs/s สูงกว่ารถเร็วสุดพอสมควร)
  - ขับย้อนทาง (ตัดเส้นสตาร์ทกลับด้าน) ไม่นับ
  - เวลาใช้ `workspace:GetServerTimeNow()`
- ข้อมูลที่ส่งให้ client: **ใช้ attribute บน model รถ** (ไม่ต้องมี remote ใหม่)
  - `LapStart` (server time ของการเริ่มรอบปัจจุบัน หรือ nil ยังไม่เริ่ม)
  - `NextCheckpoint` (number), `CheckpointCount` (number)
  - `LastLap` (number? วินาที), `BestLap` (number? วินาทีของรถคันนี้)
  - `LapCount` (number รอบที่จบในเซสชันนี้)
- เมื่อจบรอบแล้วเป็นสถิติใหม่ → `Notify` key `notify_track_best` พร้อมเวลา (format `m:ss.mmm`) และ `Effect` แบบเดิมที่ใช้ตอนอัปเกรดก็ได้
- **บันทึกสถิติ:** `PlayerData` เพิ่ม field `bestLaps: { [string]: number }` (default `{}`) ใส่ใน type `Data`, defaults และให้ `reconcile` เติมให้ save เก่า เก็บเฉพาะเวลาที่ดีที่สุดต่อ `carId`
  - **ไม่มีรางวัลเงิน** (ผู้ใช้เลือกแล้ว)
  - snapshot: เพิ่ม `bestLaps` ให้ client (ใช้แสดงในเมนู Tuning ถ้าต้องการ — ไม่บังคับ)
- เก็บกวาด state ของรถเมื่อ despawn/ผู้เล่นออก

### B.6 HUD จับเวลา (`DriveHUD.luau`)
- แสดงเฉพาะตอนนั่ง `DriveSeat` และรถมี `OnTrack = true` วางกลางด้านบนจอ ไม่ทับ HUD เงิน/ดาวเดิม (ดูตำแหน่งใน `HUD.luau`)
- แสดง:
  - เวลารอบปัจจุบัน (คำนวณ client จาก `LapStart` กับ `workspace:GetServerTimeNow()` อัปเดตทุกเฟรม)
  - รอบที่ดีที่สุด (`BestLap`)
  - checkpoint `NextCheckpoint-1 / CheckpointCount`
  - เมื่อจบรอบ: กระพริบเวลารอบล่าสุดสีเขียวถ้าเป็นสถิติใหม่ ไม่งั้นสีขาว + ส่วนต่าง (+0.532 แดง / −0.210 เขียว) เทียบกับสถิติก่อนหน้า
  - ก่อนเริ่มรอบแรก: ข้อความ "ขับผ่านเส้นสตาร์ทเพื่อเริ่มจับเวลา"
- ใช้ `Theme` และ `Localizer` เหมือนส่วนอื่นของ DriveHUD, ใช้ได้กับจอมือถือ

### B.7 Strings ที่ต้องเพิ่ม (th / en)
| key | th | en | ไฟล์ |
|---|---|---|---|
| `unlock_RaceTrack` | สนามแข่งส่วนตัว | Private race track | Strings |
| `notify_need_track` | ต้องซื้อสนามแข่งก่อน | Buy the race track first | Strings |
| `notify_track_best` | สถิติใหม่! %s | New best lap! %s | Strings |
| `tuning_drive_track` | ขับในสนาม | TRACK | StringsTuning |
| `track_lap` | รอบนี้ | Lap | StringsUI |
| `track_best` | ดีที่สุด | Best | StringsUI |
| `track_checkpoint` | จุดเช็ก | Checkpoint | StringsUI |
| `track_start_hint` | ขับผ่านเส้นสตาร์ทเพื่อเริ่มจับเวลา | Cross the start line to begin timing | StringsUI |

(ไฟล์ Strings ใช้ placeholder แบบ `string.format` คือ `%s` / `%d` เช่น `notify_upgraded = "%s อัปเกรดเป็นเลเวล %d แล้ว!"`)

### เกณฑ์ผ่านส่วน B
- ก่อนซื้อห้อง Tuning: ไม่เห็นปุ่มซื้อสนาม, ลูกศรนำทางไม่ชี้ไปสนาม
- ซื้อสนาม $150K → สนามโผล่, ประตูหลังห้องเปิด เดินออกไปดูสนามได้
- เมนู Tuning มีปุ่ม "ขับในสนาม" → รถเกิดที่จุดสตาร์ท หันถูกทาง
- วิ่งครบรอบ → HUD แสดงเวลา, สถิติถูกบันทึก, ออกเกมแล้วกลับมายังอยู่
- ลัดสนาม/ขับย้อน → ไม่นับรอบ
- Rebirth → สนามยังอยู่ (ไม่ต้องซื้อใหม่) และ rebirth ไม่บังคับให้ซื้อสนาม
- กด Return → กลับไปที่คอมพิวเตอร์ Tuning รถโชว์กลับมาบนแท่น
- Output ไม่มี error/warning ใหม่

---

## ส่งงาน
เมื่อเสร็จให้สรุปสั้น ๆ:
1. ไฟล์ที่แก้/สร้าง
2. ความยาวรอบสนามที่ได้ และจำนวน Part ของสนาม
3. สิ่งที่ทดสอบแล้วใน Studio กับสิ่งที่ยังไม่ได้ทดสอบ
4. จุดที่ตัดสินใจเองนอกเหนือจาก spec พร้อมเหตุผล
