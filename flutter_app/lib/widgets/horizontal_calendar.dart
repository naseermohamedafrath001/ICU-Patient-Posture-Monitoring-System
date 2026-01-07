import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HorizontalCalendar extends StatefulWidget {
  final DateTime initialDate;
  final Function(DateTime) onDateSelected;

  const HorizontalCalendar({
    super.key,
    required this.initialDate,
    required this.onDateSelected,
  });

  @override
  State<HorizontalCalendar> createState() => _HorizontalCalendarState();
}

class _HorizontalCalendarState extends State<HorizontalCalendar> {
  late DateTime _selectedDate;
  late DateTime _focusedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _focusedDate = widget.initialDate;
  }

  void _onDateTap(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    widget.onDateSelected(date);
  }

  void _previousWeek() {
    setState(() {
      _focusedDate = _focusedDate.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      _focusedDate = _focusedDate.add(const Duration(days: 7));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get the Monday of the current focused week
    final int dayOffset = _focusedDate.weekday - DateTime.monday;
    final DateTime firstDayOfWeek = _focusedDate.subtract(Duration(days: dayOffset));

    return Column(
      children: [
        // Header: Month Year + Arrows
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMMM yyyy').format(_focusedDate),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Gilroy',
                  color: Color(0xFF1E293B),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Color(0xFF94A3B8)),
                    onPressed: _previousWeek,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Color(0xFF1E293B)),
                    onPressed: _nextWeek,
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Days Row
        SizedBox(
          height: 100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final date = firstDayOfWeek.add(Duration(days: index));
              final isSelected = DateUtils.isSameDay(date, _selectedDate);
              final dayName = DateFormat('E').format(date); // Mon, Tue, etc.
              final dayNumber = date.day.toString();

              return GestureDetector(
                onTap: () => _onDateTap(date),
                child: Container(
                  width: 45,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ] : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(
                        dayName,
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'Gilroy',
                          color: isSelected 
                            ? const Color(0xFF1E293B) 
                            : const Color(0xFF94A3B8),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected 
                            ? Theme.of(context).colorScheme.primary 
                            : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          dayNumber,
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: 'Gilroy',
                            color: isSelected ? Colors.white : const Color(0xFF1E293B),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
