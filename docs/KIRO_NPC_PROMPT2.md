# งานสำหรับ Kiro รอบ 2: ของที่ข้ามไปจาก NPC (3 ข้อ)

## บริบท
- โปรเจกต์ Roblox (Rojo + Luau `--!strict`) รอบก่อนทำ NPC 5 ข้อเสร็จแล้ว (ดู `docs/TODO.md` §8.6) รอบนี้ทำ 3 ข้อที่ข้ามไป
- อ่าน `docs/KIRO_NPC_PROMPT.md` (กติกาเดิม) และ `docs/TODO.md` §8.6 ก่อนเริ่ม กติกาเดิมยังใช้ทั้งหมด ยกเว้นข้อห้ามเรื่องเสียงที่ปรับตามข้อ C ด้านล่าง
- โค้ดที่เกี่ยวข้อง: `src/server/Npc/NpcBuilder.luau`, `src/server/Services/EmployeeService.luau`, `src/server/Services/ShopperService.luau`, `src/server/Services/RepairService.luau`, `src/shared/Config/Game.luau`

## กติกาที่ต้องทำตาม (ทบทวน)
1. **ใช้เฉพาะ Enum/property ที่มีจริงใน Roblox** ถ้าไม่แน่ใจให้ตรวจเอกสารก่อน (เคยพังเพราะ `Material.Rust`)
2. `--!strict` ต้องไม่มี type error สไตล์เหมือนไฟล์เดิม (tab, คอมเมนต์ภาษาอังกฤษสั้น ๆ)
3. ห้ามเพิ่ม loop ต่อ NPC ใช้ Heartbeat ตัวเดียวที่มีอยู่ (`step`/`activeRigs`) หรือลูปต่อ plot ที่มีอยู่แล้ว
4. ทุกอย่างที่สร้างใหม่ต้องถูกเก็บกวาดเมื่อ NPC ถูก Destroy
5. ห้ามเพิ่ม RemoteEvent ใหม่
6. ห้ามแตะ `GarageTycoon.rbxlx`, ห้าม `git commit`, ห้ามแก้ไฟล์ที่ไม่เกี่ยว
7. API เดิมของ `NpcBuilder` (`walkCycle / idle / work / setCarry / place / turnTo / walkPath / lookAt / setHold / setStoop / setStrikeHandler`) ต้องเรียกแบบเดิมได้

---

## ข้อ A — สีละอองช่างพ่นสีให้ตรงสีรถ
ตอนนี้ `EmployeeService.setWorking` ตั้งสี emitter จากแอตทริบิวต์ `NpcShirt` (สีชุดช่าง) ต้องเปลี่ยนเป็นสีของรถคันที่กำลังพ่น

- `EmployeeService.setWorking(model: Model, working: boolean, tint: Color3?)` เพิ่มพารามิเตอร์ที่ 3 แบบ optional (เรียกแบบเดิมต้องไม่พัง)
  - ถ้ามี `tint` ให้ใช้เป็นสีละออง (`ColorSequence.new(tint:Lerp(Color3.new(1,1,1), 0.45), tint)` ตามสไตล์เดิม) ถ้าไม่มีให้ fallback เป็น `NpcShirt` เหมือนเดิม
- `RepairService.step()` (บรรทัดประมาณ 134, `pcall(EmployeeService.setWorking, npc, true)`) ให้ส่งสีรถของงานนั้นเข้าไป
  - สีรถ: ดูใน `src/shared/CarBuilder.luau` ว่าสีตัวถังเก็บที่ชิ้นไหน (ชิ้นส่วนชื่อ `Body` / `BodyPanel`) ทำฟังก์ชันช่วยเล็ก ๆ อ่าน `Color` ของชิ้นนั้นจาก `job.model` (หา part ไม่เจอ → ส่ง `nil` ไม่ error)
  - ทำฟังก์ชันช่วยไว้ที่เดียว (ใน `RepairService` หรือ `CarBuilder` ตามที่เหมาะสม) ไม่ต้อง copy ไปหลายที่
- ช่างพ่นสีคนเดียวพ่นรถหลายคัน (คันต่อคัน) สีต้องอัปเดตทุกครั้งที่เริ่มงานใหม่ ไม่ใช่ตั้งครั้งเดียวแล้วค้าง
  - ระวัง: `setWorking` มีเงื่อนไข `state.working == working` return เร็ว ถ้า NPC ยัง working อยู่แล้ว (งานใหม่ต่อทันที) สีจะไม่ถูกตั้งใหม่ ตรวจเคสนี้ให้ถูก (เช่น แยกฟังก์ชันตั้งสีออกมา หรืออัปเดตสีก่อน return)
- ถ้ารถถูกทาสีเปลี่ยนสีระหว่างงาน (ถ้าระบบมี) ให้ใช้สีล่าสุด ไม่ต้องทำ live update ถ้าไม่มีระบบแบบนั้น

---

## ข้อ B — ลูกค้าเดินสวนกันแล้วเบี่ยงข้าง
เป้าหมาย: ลูกค้า 2 คนที่เดินสวนทางกันบนเส้นทางเดียวกันต้องไม่เดินทะลุตัวกัน

ข้อมูลที่มีอยู่:
- `ShopperService` มี `live[plotIndex]` เก็บ Model ลูกค้าที่กำลังเดินอยู่ของแต่ละ plot
- เส้นทางมาจาก `Layout.SHOPPER_PATH` + จุดหน้าชั้น เดินด้วย `NpcBuilder.walkPath(model, walk, points, speed, shouldStop, finalLook?)`

แนวทางที่แนะนำ (ปรับได้ถ้ามีวิธีที่ดีกว่า แต่ต้องบอกเหตุผล):
- ทุกคนเบี่ยงไปทาง **ขวาของทิศเดินตัวเอง** เสมอ เมื่อมีอีกคนที่ "เดินสวนทาง" อยู่ในระยะ ~5 studs (เบี่ยงทางเดียวกัน = ไม่ต้องตกลงกัน ไม่ชนกัน)
  - "สวนทาง" = เวกเตอร์ความเร็วสองคนหันหน้าเข้าหากัน (dot ของทิศเดิน < -0.3) ไม่ใช่เดินตามหลังกัน
- เป็นการ **เลื่อนด้านข้าง (lateral offset)** ของตำแหน่งที่ `walkPath` คำนวณอยู่แล้ว สูงสุดไม่เกิน ~1.2 studs และต้องปรับแบบนุ่ม (lerp เข้า-ออก ไม่กระตุก) ห้ามเปลี่ยนจุดปลายทางจริง
- ตรวจแบบถี่ต่ำ (เช่น ทุก 0.2–0.3 วินาที) และคิดต่อ plot ไม่ใช่ต่อ NPC ห้ามสร้าง garbage ต่อเฟรม (ใช้ตัวแปรเก็บ offset ปัจจุบันต่อการเดินแต่ละครั้ง)
- ต้องไม่ทำให้ลูกค้าเดินทะลุกำแพง/ชั้น: ตรวจ `Layout.SHOPPER_PATH` และตำแหน่งชั้นก่อน ถ้าทางแคบ ให้จำกัดระยะเบี่ยงให้พอดี
- เมื่อไม่มีคนสวน offset ต้องค่อย ๆ กลับ 0 ก่อนถึงจุดหยุดหน้าชั้น (ปลายทางต้องตรงจุดเดิม)
- API ที่เพิ่มได้: ตัวเลือกใหม่ใน `walkPath` (เช่นพารามิเตอร์ `avoid: ((Vector3) -> number)?` คืน offset ด้านข้าง) หรือฟังก์ชันภายใน `ShopperService` ที่ส่งเข้า `shouldStop` ลักษณะเดียวกัน เลือกแบบที่เปลี่ยน API น้อยที่สุด อย่าทำให้ `EmployeeService.stockLoop` ที่ใช้ `walkPath` อยู่พัง

สิ่งที่ไม่ต้องทำ: ลูกค้ากับพนักงาน หรือกับผู้เล่น ไม่ต้องหลบ เฉพาะลูกค้ากับลูกค้า

---

## ข้อ C — เสียงทั้งหมด (โครงที่ผู้ใช้ใส่ ID เองทีหลัง)
ปัญหา: ไม่มีใครตรวจ ID เสียงของ Roblox จากในโค้ดได้ **ห้ามเดา/แต่ง ID เด็ดขาด** (ID ที่ผิดจะเงียบหรือเล่นเสียงแปลก ๆ) ดังนั้นทำ "โครง" ให้พร้อม key ที่ผู้ใช้ยังไม่มี ID ให้ปิดไว้ (ว่าง) ส่วน 8 key ในข้อ C.0 ผู้ใช้อัปโหลดแล้ว มี ID ให้ใส่เลย

### C.0 ไฟล์เสียงร่างที่เตรียมไว้แล้ว (ไม่ต้องสร้างเอง)
Claude สร้างไฟล์ `.wav` สังเคราะห์ไว้ที่ `assets/sounds_draft/` ด้วยสคริปต์ `tools/make_sounds.py` (ห้ามแก้/ลบสองที่นี้) ผู้ใช้จะอัปโหลดขึ้น Roblox เองแล้วนำ ID มาใส่ `Sounds.luau` ชื่อไฟล์ตรงกับ key ใน config เป๊ะ:

| ไฟล์ | key | ความยาว | หมายเหตุ |
|---|---|---|---|
| `hammerStrike.wav` | `hammerStrike` | 0.35s | ยิงครั้งเดียวต่อค้อนกระทบ |
| `wrench.wav` | `wrench` | 0.5s | เสียงขันประแจ เล่นเป็นช่วง ๆ ตอนช่างใช้ประแจ |
| `spray.wav` | `spray` | 1.6s | **ลูปได้ไร้รอยต่อ** ตั้ง `Looped = true` |
| `greet.wav` | `greet` | 0.7s | ระฆังเบา ๆ |
| `crateDrop.wav` | `crateDrop` | 0.4s | |
| `shopperBuy.wav` | `shopperBuy` | 0.5s | |
| `repairDone.wav` | `repairDone` | 1.0s | |
| `purchase.wav` | `purchase` | 0.8s | ฝั่ง client |

เพราะ `hammerStrike` ยาวแค่ 0.35s และค้อนตีทุก ~0.9s (`HAMMER_RATE`) จึงไม่ซ้อนกันเอง แต่ยังต้องมี cooldown ใน helper ตามด้านล่าง
**อัปโหลดแล้ว (Asset ID จริงของผู้ใช้ ตรวจแล้วว่าเป็นของบัญชีเขาเอง)** ให้ใส่ใน `Sounds.luau` เป็น `"rbxassetid://<เลข>"` ทันที ไม่ต้องเว้นว่าง (ข้อห้ามเดา ID ใช้กับ key อื่นที่ไม่มีในตารางนี้เท่านั้น):

| key | ID |
|---|---|
| `purchase` | 115870602105854 |
| `crateDrop` | 84092922276822 |
| `hammerStrike` | 115558479847711 |
| `repairDone` | 100620890674842 |
| `greet` | 122293261122306 |
| `shopperBuy` | 92843313807987 |
| `wrench` | 130619859186477 |
| `spray` | 78380289112926 |

ตัวเลขเหล่านี้อ่านจากภาพหน้าจอ ให้เก็บไว้ในค่าคงที่ส่วนบนสุดของ `Sounds.luau` ที่เดียว (แก้ได้ง่ายถ้าผู้ใช้พบว่าตัวเลขผิดหลัก) และในรายงานท้ายงานให้ขึ้นบรรทัดว่า "ID จากภาพหน้าจอ ผู้ใช้ต้องตรวจกับหน้า Creator Hub อีกครั้ง"

ค่า `volume` เริ่มต้นใน config ให้ตั้งเผื่อไว้ (0.4–0.7) เพราะไฟล์ normalize ไว้ที่ peak 0.85 ผู้ใช้จะปรับเองหลังฟังใน Studio

### C.1 ไฟล์ config
สร้าง `src/shared/Config/Sounds.luau` (`--!strict`) รูปแบบเดียวกับ config อื่น เช่น

```lua
return {
	-- 0 or "" = off. Paste "rbxassetid://123..." once the sound has been checked in Studio.
	hammerStrike = { id = "", volume = 0.6, pitchJitter = 0.1 },
	spray = { id = "", volume = 0.35, looped = true },
	...
}
```

อย่างน้อยให้มีรายการเหล่านี้ (เพิ่มได้ถ้าเหมาะสม แต่อย่าเพิ่มเกินจำเป็น):

| key | ใช้เมื่อ | ตำแหน่งเล่น |
|---|---|---|
| `hammerStrike` | ค้อนกระทบ (ใน strike handler ที่ปล่อยประกายอยู่แล้ว) | ที่ NPC ช่าง (3D) |
| `wrench` | (ถ้าทำได้) ช่างใช้ประแจ เป็นระยะ | ที่ NPC ช่าง |
| `spray` | ช่างพ่นสี ตอน `setWorking(true)` วนเล่น หยุดเมื่อ false | ที่ NPC ช่างพ่นสี |
| `greet` | แคชเชียร์/พนักงานต้อนรับโบกมือทักผู้เล่น | ที่ NPC |
| `crateDrop` | stocker วางกล่องลง | ที่ NPC |
| `shopperBuy` | ลูกค้าหยิบของหน้าชั้น/จ่ายเงิน | ที่ลูกค้า |
| `repairDone` | งานซ่อมเสร็จ | ตามที่ระบบเดิมเหมาะสม |
| `purchase` | ซื้อ unlock/อัปเกรดสำเร็จ | ฝั่ง client |

ผู้ใช้อาจขอเพิ่มทีหลัง ดังนั้นโครงต้องเพิ่ม key ใหม่ง่าย (บรรทัดเดียวใน config + 1 call)

### C.2 ตัวเล่นเสียง
- ทำ helper เล็ก ๆ ตัวเดียว (เช่น `src/shared/SoundFx.luau`) ฟังก์ชัน `SoundFx.play(parent: Instance, key: string)` และ/หรือ `SoundFx.attach(parent, key): Sound?` สำหรับเสียง loop
  - ถ้า `id` ว่าง/0 → **คืน nil ทันที ไม่สร้าง Instance ใด ๆ**
  - สร้าง `Sound` ใต้ `parent` (เช่น part ของ NPC เพื่อให้เป็นเสียง 3D) ตั้ง `RollOffMaxDistance` พอประมาณ (~60), `pitch` สุ่มเล็กน้อยตาม `pitchJitter`, ใช้ `Debris` หรือ `Ended` เก็บกวาดเสียงที่ไม่ loop
  - **จำกัดจำนวนเสียงที่เล่นพร้อมกันต่อ key** (เช่น cooldown 0.08 วินาที ต่อ key ต่อ parent) กันค้อนหลายตัวเล่นรัวทับกัน
  - เสียง loop (spray) เก็บใน state ของ NPC แล้ว Stop/Destroy ตอน `setWorking(false)` และตอน NPC ถูก Destroy
- ฝั่ง server ที่ parent Sound ไว้ใน part ของ NPC เสียง replicate ไป client เอง ไม่ต้องใช้ Remote
- เสียง UI (`purchase`) เล่นฝั่ง client ผ่าน `Effects.luau` / controller ที่มีอยู่ ใช้ helper เดียวกัน ห้ามสร้างระบบเสียงที่สอง
- เสียงเดิมที่ใช้ `rbxasset://sounds/electronicpingshort.wav` ใน `Effects.luau` ปล่อยไว้ตามเดิม ห้ามแตะ
- ตัวแปร `Game.MUSIC_SOUND_ID` ปล่อยไว้ตามเดิม

### C.3 ต่อเข้ากับโค้ดจริง
- `hammerStrike`: ใน `NpcBuilder.setStrikeHandler` callback ที่ `EmployeeService` ตั้งไว้ (ที่ปล่อยประกาย) เพิ่มเรียกเสียงด้วย
- `spray`: ใน `EmployeeService.setWorking` เมื่อ painter เริ่ม/หยุดทำงาน
- `greet`: จุดเรียก `idle.wave` ใน `greetStep`
- `crateDrop`: จุดที่ stocker ปล่อยกล่องใน `stockLoop`
- `shopperBuy`: จุดที่ลูกค้าหยุดหน้าชั้นใน `ShopperService.runVisit`
- ที่เหลือหาจุดที่ระบบเดิมมีอยู่แล้ว ถ้าไม่มีจุดชัดเจน **ข้ามและจดใน TODO** อย่าสร้าง event ใหม่เพื่อเสียงอย่างเดียว

### C.4 ทดสอบโครง
key ใดที่ ID ว่าง ต้องเงียบและไม่มี warning/error ใหม่ ส่วน 8 key ที่มี ID ต้องเล่นได้เมื่อ Play ใน Studio ให้เขียนใน TODO ว่าสิ่งที่ต้องฟังตรวจมีอะไรบ้าง (ค้อนกระทบ, สเปรย์วน, ทักทาย, ลังตก, ลูกค้าซื้อ, ซ่อมเสร็จ, ซื้อของ)

---

## ส่งมอบ
1. แก้เฉพาะ: `src/server/Npc/NpcBuilder.luau`, `src/server/Services/EmployeeService.luau`, `src/server/Services/ShopperService.luau`, `src/server/Services/RepairService.luau`, `src/client/...Effects` (เฉพาะส่วนที่ต้องต่อเสียงซื้อของ), ไฟล์ใหม่ `src/shared/Config/Sounds.luau` และ `src/shared/SoundFx.luau` กับ `docs/TODO.md` ถ้าต้องแตะไฟล์อื่น ให้บอกเหตุผล
2. เพิ่มหัวข้อ "วิธีอัปโหลดเสียง" ใน `docs/TODO.md`: เปิด Creator Hub → Creations → Development Items → Audio → Upload ลากไฟล์จาก `assets/sounds_draft/` ทีละไฟล์ (ฟรี รออนุมัติสักครู่) → คัดลอก Asset ID → ใส่ `"rbxassetid://<เลข>"` ใน `src/shared/Config/Sounds.luau` ตรงกับ key → Play ใน Studio ฟังแล้วปรับ `volume`
3. แก้ `docs/TODO.md` §8.6: เปลี่ยนรายการที่ข้ามไปเป็น 🟡 (โค้ดเสร็จ ยังไม่ได้ทดสอบ Studio) พร้อมเขียนว่าเสียงรอ ID จากผู้ใช้ และใส่ตารางว่า key ไหนใช้กับจุดไหน
4. ท้ายงานรายงานสั้น ๆ: ไฟล์ที่แก้, ฟังก์ชันใหม่, จุดที่ข้าม, สิ่งที่ยังไม่ได้ทดสอบใน Studio
5. อย่า commit
