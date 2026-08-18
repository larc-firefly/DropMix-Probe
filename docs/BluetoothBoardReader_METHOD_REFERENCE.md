# `BluetoothBoardReader` method reference

This is the complete inventory of the 231 methods directly on the Android
DropMix app's recovered `BluetoothBoardReader` IL2CPP type. It excludes nested
types, compiler-generated helpers, and the Android Java Bluetooth plug-in.

`named` means the released app retained a readable name. `obfuscated` means the
name alone does not establish behaviour; it requires native-code analysis or a
runtime trace. This documents the real app surface without publishing its
binary.

## Recovered states and controls

| Area | Named methods | Evidence of state/control |
| --- | --- | --- |
| Discovery | `Scan`, `RestartScan`, `StopScan`, `IsScanning`, `HasFoundDevice`, `GetFoundDeviceName`, `GetFoundDeviceRSSI` | scanning and a selected board are separate. |
| Bond and connection | `IsBonded`, `ClearBondedDevices`, `ConnectToFoundDevice`, `Disconnect`, `IsConnected`, `IsConnectionFailed`, `ReconnectAfterFailure`, `InBluetoothMode`, `NeedToWaitForBLE` | bonding, link connection, and failure/retry are distinct. |
| Board readiness | `IsBoardReady`, `HasReadFirmwareVersion`, `GetFirmwareVersion`, `GetTxPowerLevel`, `GetPreferredConnectionPriority` | a connected BLE peripheral is not automatically a ready board. |
| Card signatures | `RequestSignatureRead`, `CancelSignatureRead`, `IsSignatureReadAborted`, `IsVerifyingSignatures`, `IsSignatureVerified`, `IsSignatureFailed`, `ClearSignatureInformation` | card-signature work is a separate state machine, not evidence of BLE authentication. |
| Slots | `ClearSlots`, `GetSlotStack`, `GetStackGuids`, `GetRawStackCount`, `GetStackReadSize`, `SetStackReadSize`, `GetShouldReadGuids`, `AddReadGuidsReason`, `RemoveReadGuidsReason`, `GetSlotError`, `SetSlotError`, `ShouldIgnoreBoardSlot`, `RemapSlotForLights` | per-slot stacks, errors, GUID reads, and light mapping are tracked. |
| Board events | `WasEQPressed`, `WasMotionSensorTriggered`, `GetOutOfRangeTimer` | equalizer button, motion, and range state exist. |
| Traffic | `SendByte`, `SendBytes` | explicit byte and byte-array sends exist; packet meaning still needs traces. |
| Maintenance | `get_OTAUpdater`, `get_IsUpdatingFirmware`, debug setters/getters, `OnApplicationPause` | OTA, diagnostics, and lifecycle handling are integrated. |

```text
not scanning -> scanning -> board discovered -> bonded -> connected
  -> services/board data available -> IsBoardReady -> card/slot activity
```

See [the protocol reference](PROTOCOL_NOTES.md) for GATT layout, the Android
bond flow, observed packets, and the macOS implementation limits.

## Complete inventory

```text
  1 MDFEAALMLMN [obfuscated]              2 HGAJLMHPIKE [obfuscated]
  3 KHGEJEMOHKD [obfuscated]              4 MHFLFFAEDFB [obfuscated]
  5 EDJJLNLJIBM [obfuscated]              6 NOPGHHCMCJK [obfuscated]
  7 KBPJIGEBGAF [obfuscated]              8 NGKOKGPGAPO [obfuscated]
  9 LateUpdate [named lifecycle]         10 KOOIGNLGGKO [obfuscated]
 11 GetFirmwareVersion [named]           12 BFKOEBNBIAP [obfuscated]
 13 GetTxPowerLevel [named]              14 ELAPCFFCPJD [obfuscated]
 15 GetSlotError [named]                 16 JOLJAIOGAKH [obfuscated]
 17 PJDANHPGDME [obfuscated]             18 JPNOLMFOAMA [obfuscated]
 19 CBHCIIELDFP [obfuscated]             20 EIOIJILCEEF [obfuscated]
 21 LLHPMPKAKFF [obfuscated]             22 CNBDENHMHFJ [obfuscated]
 23 PJCKJKPJKOE [obfuscated]             24 Awake [named lifecycle]
 25 IsSignatureReadAborted [named]        26 NLBIPKEIGGA [obfuscated]
 27 GKOJJHHPKGG [obfuscated]             28 CancelSignatureRead [named]
 29 GMGEDJKEHME [obfuscated]             30 RemapSlotForLights [named]
 31 PNKKJKEHCGB [obfuscated]             32 IAPFOEBGPOP [obfuscated]
 33 KMKLDAEAPCH [obfuscated]             34 FMGLIKCLIEJ [obfuscated]
 35 HGBHKNENIGF [obfuscated]             36 AddReadGuidsReason [named]
 37 MBKFMDOBCJN [obfuscated]             38 DLKIPFLNIEJ [obfuscated]
 39 HBFIFGGPCKN [obfuscated]             40 JGBIFDAMPAA [obfuscated]
 41 CPLACMPEIKM [obfuscated]             42 OnGUI [named lifecycle]
 43 GetStackGuids [named]                 44 KPAMIGLIDGP [obfuscated]
 45 ClearSignatureInformation [named]     46 OBOCOICGIKJ [obfuscated]
 47 CHLNLIPHKOG [obfuscated]             48 HasFoundDevice [named]
 49 ADGEAFEMJOG [obfuscated]             50 HIOLGAFLBDA [obfuscated]
 51 NBDBPMKMMLH [obfuscated]             52 BKEBMGGKENK [obfuscated]
 53 GetFoundDeviceName [named]            54 RestartScan [named]
 55 GetStackReadSize [named]              56 BHADDMDCMIO [obfuscated]
 57 ClearBondedDevices [named]            58 KLNKGOALAFA [obfuscated]
 59 DFCIENGCEAK [obfuscated]             60 StopScan [named]
 61 JFBJFKFGCOL [obfuscated]             62 ICEDKDPOJGJ [obfuscated]
 63 RequestSignatureRead [named]          64 AOMKBDCCGOA [obfuscated]
 65 LJIBNOCBKFN [obfuscated]             66 KPDENHCOKBL [obfuscated]
 67 KFLGKLMEFCG [obfuscated]             68 KAJEHBEEDOD [obfuscated]
 69 GetFoundDeviceRSSI [named]            70 AOPKMPOLHLL [obfuscated]
 71 AILGCOGMMPG [obfuscated]             72 HasReadFirmwareVersion [named]
 73 HHMKALOFPIM [obfuscated]             74 HDCGKDOHMKD [obfuscated]
 75 IsBonded [named]                      76 DONHIGMEDLN [obfuscated]
 77 MIFHMBPFIGE [obfuscated]             78 LGMAMCMPPLP [obfuscated]
 79 BEMEFFEOAAH [obfuscated]             80 OJCFMECBEEO [obfuscated]
 81 PEALJACOGJO [obfuscated]             82 GLEDJFLFNKL [obfuscated]
 83 IMAFOMKBBBD [obfuscated]             84 AIFFPJJGIEI [obfuscated]
 85 ELKFFGBDDPA [obfuscated]             86 EHBEMPDFGGI [obfuscated]
 87 ONCNLNPCGFA [obfuscated]             88 PAJIBELMPGI [obfuscated]
 89 IsVerifyingSignatures [named]         90 IsConnectionFailed [named]
 91 ClearSlots [named]                    92 JAIGNOJNODD [obfuscated]
 93 GetSlotStack [named]                  94 RemoveReadGuidsReason [named]
 95 LAOFBHDMNDD [obfuscated]             96 DIJNOGMIIGD [obfuscated]
 97 JLBBFLIHDPK [obfuscated]             98 SendByte [named]
 99 NeedToWaitForBLE [named]             100 IsConnected [named]
101 ILCGGHEPGDF [obfuscated]            102 DAFFJGBMHLN [obfuscated]
103 CFCNHLCIJLJ [obfuscated]            104 JGJHPABCKHP [obfuscated]
105 HJHMILIMDIB [obfuscated]            106 AOKMAGEDHBD [obfuscated]
107 LDBHBNPFJGF [obfuscated]            108 NDPNEAEKKBD [obfuscated]
109 JLPEDFOLIPD [obfuscated]            110 NGHJKPCKBJL [obfuscated]
111 MILLEEIIPKJ [obfuscated]            112 GetStackHistoryDebug [named]
113 NCJMKECELND [obfuscated]            114 get_OTAUpdater [named]
115 JOBDFMIHFKH [obfuscated]            116 IsSignatureVerified [named]
117 PAFEIIDFIDI [obfuscated]            118 IDMJDPELOOC [obfuscated]
119 ReconnectAfterFailure [named]        120 SetStackHistoryDebug [named]
121 HEEBHMNBALE [obfuscated]            122 PCDGEOMBMKB [obfuscated]
123 MOONPDECFOF [obfuscated]            124 HJOHGDEDJLP [obfuscated]
125 AKMPNNJFLLL [obfuscated]            126 MGCBJFJDAAP [obfuscated]
127 CGAKBGOBAEG [obfuscated]            128 BKOMEGNHDGE [obfuscated]
129 NFOLNPLLGGC [obfuscated]            130 ShouldIgnoreBoardSlot [named]
131 HEGAMKAKKOI [obfuscated]            132 PNLLNCIIMPO [obfuscated]
133 SetSlotError [named]                 134 BIPEFJPGIPL [obfuscated]
135 GPGEJBFMGLK [obfuscated]            136 PJHDLKPEBOB [obfuscated]
137 GLFJOFIMCDA [obfuscated]            138 FLPDAOOKIHJ [obfuscated]
139 GetRawStackCount [named]             140 ECCDBLHGGDG [obfuscated]
141 IFGILAMDDGK [obfuscated]            142 KGMGKEJIMND [obfuscated]
143 LINMEOPKCDL [obfuscated]            144 ECCPEPABCCM [obfuscated]
145 Scan [named]                         146 NBLNPMNDCIC [obfuscated]
147 PCKGHNIGPJA [obfuscated]            148 AJBMLBDMDMG [obfuscated]
149 EBADIOPMIMI [obfuscated]            150 Start [named lifecycle]
151 NHHFPKPLPBH [obfuscated]            152 DICGLPGEKEA [obfuscated]
153 GetPreferredConnectionPriority [named]154 GKLJOPFGFMM [obfuscated]
155 AAJKOFADAFD [obfuscated]            156 JKAOPMHNFHI [obfuscated]
157 MCPJPPHPKIE [obfuscated]            158 KDENMAJFLFB [obfuscated]
159 HDEBDFDCCKO [obfuscated]            160 GDGECHFOJMH [obfuscated]
161 FFDJPLKHDMN [obfuscated]            162 NKNGPDOBMHB [obfuscated]
163 IsSignatureFailed [named]            164 MFPCJGIJFMG [obfuscated]
165 GetPauseCommunicationsDebug [named]  166 MOIJFBBMEAG [obfuscated]
167 GetOutOfRangeTimer [named]           168 JCONLGAEOCL [obfuscated]
169 IFNNKFHDELA [obfuscated]            170 CFHIMECBEKM [obfuscated]
171 BECKIKOLNKE [obfuscated]            172 IPDACMGNPAF [obfuscated]
173 ODCNPGLADJN [obfuscated]            174 BBFLNCNKGDI [obfuscated]
175 GetCommunicationsDebug [named]       176 CJJBJDIFAKJ [obfuscated]
177 FPIBJHPCCII [obfuscated]            178 IsScanning [named]
179 ACJKJAGIACJ [obfuscated]            180 BHJDMHFFJJH [obfuscated]
181 WasEQPressed [named]                 182 NDJKOJCPOOA [obfuscated]
183 NKAFIPPABJL [obfuscated]            184 AJFIGIPNDBC [obfuscated]
185 MABPOAKHLIC [obfuscated]            186 ECFPGKKPDCN [obfuscated]
187 MHAIOONHJBP [obfuscated]            188 DENAHBHHBOI [obfuscated]
189 KMOHEFHLKND [obfuscated]            190 GetShouldReadGuids [named]
191 NBCKBPKLIML [obfuscated]            192 MBMPPGNACHM [obfuscated]
193 MGFJGPHNLED [obfuscated]            194 OPNJMDCJEOP [obfuscated]
195 GDBPHHENDOE [obfuscated]            196 LLCCLKPGAHL [obfuscated]
197 IsBoardReady [named]                 198 ANDOKFCLKBO [obfuscated]
199 DCENBOJPKCD [obfuscated]            200 OnApplicationPause [named lifecycle]
201 FKFAAIMMDBK [obfuscated]            202 IAHFMANJIDH [obfuscated]
203 CEECGDCCBLI [obfuscated]            204 SetCommunicationsDebug [named]
205 LKIFNEDIADI [obfuscated]            206 NCLMMEDAABA [obfuscated]
207 JONMOPAFFEC [obfuscated]            208 NHBPFEMIJBK [obfuscated]
209 AEKPMKIBHAJ [obfuscated]            210 get_IsUpdatingFirmware [named]
211 .ctor [constructor]                  212 IILAKELCMBP [obfuscated]
213 IFHDMDJNCOL [obfuscated]            214 ELJICBAMBGG [obfuscated]
215 ShouldIgnoreBoard [named]            216 JEFKNPLBDNM [obfuscated]
217 WasMotionSensorTriggered [named]     218 DADOOHKMDJA [obfuscated]
219 LBIDGHPKMKL [obfuscated]            220 DEKHCLELJIL [obfuscated]
221 OLHKJICCNNA [obfuscated]            222 SetStackReadSize [named]
223 ILNDJBKHALH [obfuscated]            224 SetPauseCommunicationsDebug [named]
225 ConnectToFoundDevice [named]         226 Disconnect [named]
227 SendBytes [named]                    228 GBGDNPNDAHE [obfuscated]
229 GEGMOKDJGPD [obfuscated]            230 OEGEDAOIHOK [obfuscated]
231 InBluetoothMode [named]
```

## Next decoding work

The obfuscated methods likely include GATT callback routing, packet parsing,
LED commands, and card-read sequencing. The next reliable improvement is to
correlate controlled physical-board traffic with one method at a time, rather
than assigning meanings from names alone.
