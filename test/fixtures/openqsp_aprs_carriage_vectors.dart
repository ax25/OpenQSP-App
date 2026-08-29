final class OpenQspAprsCarriageVector {
  const OpenQspAprsCarriageVector({
    required this.name,
    required this.frame,
    required this.encoded,
    required this.transactionId,
    required this.fragmentBodies,
  });

  final String name;
  final List<int> frame;
  final String encoded;
  final String transactionId;
  final List<String> fragmentBodies;
}

// Generated with the canonical Python server carriage (urlsafe_b64encode,
// padding stripped, then consecutive 48-character chunks).
const openQspAprsCarriageVectors = <OpenQspAprsCarriageVector>[
  OpenQspAprsCarriageVector(
    name: 'GET_CAPABILITIES',
    frame: [1, 5, 0, 0],
    encoded: 'AQUAAA',
    transactionId: 'ABC',
    fragmentBodies: ['Q1:ABC:00/01:AQUAAA'],
  ),
  OpenQspAprsCarriageVector(
    name: 'STORED',
    frame: [1, 68, 0, 0],
    encoded: 'AUQAAA',
    transactionId: 'ABC',
    fragmentBodies: ['Q1:ABC:00/01:AUQAAA'],
  ),
  OpenQspAprsCarriageVector(
    name: 'SEND_MESSAGE simple',
    frame: [1, 1, 0, 14, 0, 0, 0, 1, 6, 69, 65, 51, 71, 78, 85, 2, 72, 73],
    encoded: 'AQEADgAAAAEGRUEzR05VAkhJ',
    transactionId: 'ABC',
    fragmentBodies: ['Q1:ABC:00/01:AQEADgAAAAEGRUEzR05VAkhJ'],
  ),
  OpenQspAprsCarriageVector(
    name: 'SEND_MESSAGE multi-fragment',
    frame: [
      1, 1, 0, 112, 0, 1, 226, 64, 6, 69, 65, 51, 71, 78, 85, 100,
      88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88,
      88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88,
      88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88,
      88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88,
      88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88,
      88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88,
      88, 88, 88, 88,
    ],
    encoded: 'AQEAcAAB4kAGRUEzR05VZFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFg',
    transactionId: 'LNG',
    fragmentBodies: [
      'Q1:LNG:00/04:AQEAcAAB4kAGRUEzR05VZFhYWFhYWFhYWFhYWFhYWFhYWFhY',
      'Q1:LNG:01/04:WFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhY',
      'Q1:LNG:02/04:WFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhY',
      'Q1:LNG:03/04:WFhYWFhYWFg',
    ],
  ),
];
