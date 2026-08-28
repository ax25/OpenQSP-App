import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/application/messages_controller.dart';
import 'package:openqsp_app/features/messages/data/contracts.dart';
import 'package:openqsp_app/features/messages/domain/models.dart';
class FakeApi implements MessagesApi {
  List<Conversation> conversationValues=[]; List<InternetMessage> historyValues=[]; InternetMessage? sent; String? deletedMessage; String? deletedConversation;
  @override Future<List<Conversation>> conversations() async=>conversationValues;
  @override Future<void> deleteConversation(String value) async { deletedConversation=value; }
  @override Future<void> deleteMessage(String id) async { deletedMessage=id; }
  @override Future<List<InternetMessage>> history(String value) async=>historyValues;
  @override Future<InternetMessage> send(String value,String text) async=>sent!;
}
class FakeSocket implements MessagesSocket {
  final eventController=StreamController<MessagingEvent>.broadcast(); final stateController=StreamController<MessagingConnectionState>.broadcast(); String? token; bool disconnected=false;
  @override Stream<MessagingEvent> get events=>eventController.stream; @override Stream<MessagingConnectionState> get states=>stateController.stream;
  @override Future<void> connect(String value) async { token=value; } @override Future<void> disconnect() async { disconnected=true; }
}
InternetMessage message(String id,{String sender='EA3GNU',String text='hello'})=>InternetMessage(id:id,sender:sender,recipient:sender=='EA3GNU'?'N0CALL':'EA3GNU',text:text,sentAt:DateTime.utc(2026,1,int.parse(id)),canDelete:true);
void main(){
  late FakeApi api; late FakeSocket socket; late MessagesController controller;
  setUp(() { api=FakeApi(); socket=FakeSocket(); controller=MessagesController(localCallsign:'EA3GNU',api:api,socket:socket); });
  test('loads list and connects authenticated socket',() async { api.conversationValues=[const Conversation(remoteCallsign:'N0CALL')]; await controller.start('token'); expect(socket.token,'token'); expect(controller.conversations.single.remoteCallsign,'N0CALL'); controller.dispose(); await Future<void>.delayed(Duration.zero); expect(socket.disconnected,isTrue); });
  test('history is chronological and deduplicated by server id',() async { api.historyValues=[message('2'),message('1'),message('1')]; await controller.loadHistory('N0CALL'); expect(controller.messagesFor('N0CALL').map((m)=>m.id),['1','2']); });
  test('HTTP send and matching socket event appear once',() async { api.sent=message('1'); await controller.start('token'); expect(await controller.send('N0CALL','hello'),isTrue); socket.eventController.add(MessageReceived(message('1'))); await Future<void>.delayed(Duration.zero); expect(controller.messagesFor('N0CALL'),hasLength(1)); });
  test('incoming event creates unread conversation preview',() async { await controller.start('token'); socket.eventController.add(MessageReceived(message('1',sender:'N0CALL',text:'new'))); await Future<void>.delayed(Duration.zero); expect(controller.conversations.single.latestMessage!.text,'new'); expect(controller.conversations.single.unread,1); });
  test('deletes message and conversation after API success',() async { api.historyValues=[message('1')]; api.conversationValues=[const Conversation(remoteCallsign:'N0CALL')]; await controller.reload(); await controller.loadHistory('N0CALL'); expect(await controller.deleteMessage('1'),isTrue); expect(controller.messagesFor('N0CALL'),isEmpty); expect(await controller.deleteConversation('N0CALL'),isTrue); expect(controller.conversations,isEmpty); });
}
