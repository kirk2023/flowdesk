import { InputEventMessage, MOD_SHIFT, MOD_CTRL, MOD_ALT, MOD_META } from '../models/Protocol';
import { ConnectionService } from './ConnectionService';

const TAG = 'FlowDesk.Input';

export class InputService {
  private connection: ConnectionService;
  private lastMouseX: number = 0;
  private lastMouseY: number = 0;
  private screenWidth: number = 1920;
  private screenHeight: number = 1080;

  constructor(connection: ConnectionService) {
    this.connection = connection;
  }

  setScreenSize(width: number, height: number): void {
    this.screenWidth = width;
    this.screenHeight = height;
  }

  async onTouchStart(x: number, y: number, button: string): Promise<void> {
    this.lastMouseX = x;
    this.lastMouseY = y;
    const event: InputEventMessage = new InputEventMessage();
    event.type = 'input';
    event.event = 'mouse-down';
    event.x = x;
    event.y = y;
    event.button = button;
    event.ts = Date.now();
    await this.sendEvent(event);
  }

  async onTouchMove(x: number, y: number): Promise<void> {
    this.lastMouseX = x;
    this.lastMouseY = y;
    const event: InputEventMessage = new InputEventMessage();
    event.type = 'input';
    event.event = 'mouse-move';
    event.x = x;
    event.y = y;
    event.ts = Date.now();
    await this.sendEvent(event);
  }

  async onTouchEnd(button: string): Promise<void> {
    const event: InputEventMessage = new InputEventMessage();
    event.type = 'input';
    event.event = 'mouse-up';
    event.x = this.lastMouseX;
    event.y = this.lastMouseY;
    event.button = button;
    event.ts = Date.now();
    await this.sendEvent(event);
  }

  async onWheel(dx: number, dy: number): Promise<void> {
    const event: InputEventMessage = new InputEventMessage();
    event.type = 'input';
    event.event = 'mouse-wheel';
    event.dx = dx;
    event.dy = dy;
    event.ts = Date.now();
    await this.sendEvent(event);
  }

  async onKeyDown(code: number, modifiers: number): Promise<void> {
    const event: InputEventMessage = new InputEventMessage();
    event.type = 'input';
    event.event = 'key-down';
    event.code = code;
    event.modifiers = modifiers;
    event.ts = Date.now();
    await this.sendEvent(event);
  }

  async onKeyUp(code: number, modifiers: number): Promise<void> {
    const event: InputEventMessage = new InputEventMessage();
    event.type = 'input';
    event.event = 'key-up';
    event.code = code;
    event.modifiers = modifiers;
    event.ts = Date.now();
    await this.sendEvent(event);
  }

  async onPasteText(text: string): Promise<void> {
    const event: InputEventMessage = new InputEventMessage();
    event.type = 'input';
    event.event = 'paste-text';
    event.text = text;
    event.ts = Date.now();
    await this.sendEvent(event);
  }

  async onRightClick(x: number, y: number): Promise<void> {
    this.lastMouseX = x;
    this.lastMouseY = y;
    const down: InputEventMessage = new InputEventMessage();
    down.type = 'input';
    down.event = 'mouse-down';
    down.x = x;
    down.y = y;
    down.button = 'right';
    down.ts = Date.now();
    await this.sendEvent(down);
    const up: InputEventMessage = new InputEventMessage();
    up.type = 'input';
    up.event = 'mouse-up';
    up.x = x;
    up.y = y;
    up.button = 'right';
    up.ts = Date.now();
    await this.sendEvent(up);
  }

  async onLeftClick(x: number, y: number): Promise<void> {
    this.lastMouseX = x;
    this.lastMouseY = y;
    const down: InputEventMessage = new InputEventMessage();
    down.type = 'input';
    down.event = 'mouse-down';
    down.x = x;
    down.y = y;
    down.button = 'left';
    down.ts = Date.now();
    await this.sendEvent(down);
    const up: InputEventMessage = new InputEventMessage();
    up.type = 'input';
    up.event = 'mouse-up';
    up.x = x;
    up.y = y;
    up.button = 'left';
    up.ts = Date.now();
    await this.sendEvent(up);
  }

  static readonly MOD_SHIFT: number = MOD_SHIFT;
  static readonly MOD_CTRL: number = MOD_CTRL;
  static readonly MOD_ALT: number = MOD_ALT;
  static readonly MOD_META: number = MOD_META;

  private async sendEvent(event: InputEventMessage): Promise<void> {
    await this.connection.sendInputEvent(event);
  }
}
