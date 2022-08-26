# Timers and time management
## Instroduction
时间子系统主要包含两种设备，对应kernel中的概念分别为clocksource, timer
* clocksource: 时钟源，可以理解为生活中所见的"墙上挂钟", 他们提供了时间(时刻),
  kernel 可以通过时钟源获取当前时间，常见的clocksource有:
	* TSC : Timer Stamp Counter
	* RTC : Real Time Clock
	* ACPI PM
* timer: 定时器, 可以理解为生活中的"闹钟", 他们周期性(periodic)
	或者一次性(oneshot)在设置的时间间隔后通知到期事件。kernel 可以通
	过定时器设置 expired time, 从而在timer到期时, 获取得到时钟中断。
	常见的timer 有:
	* local APIC Timer
	* PIT
	* HPET
