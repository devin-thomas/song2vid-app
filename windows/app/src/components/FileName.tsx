import { Tip } from './ui';

/**
 * A chosen file's name, cut in the middle when the room is short so its start and its extension both stay
 * ("A very long photograph na…ame.jpg"), with the whole name in the tooltip. The two parts read as one name:
 * the text of the element is the file's name exactly. A file the tool cannot use is marked, not just listed.
 */
export function FileName({ name, kind, problem }: { name: string; kind: 'audio' | 'image'; problem: boolean }) {
  const chars = Array.from(name);
  const split = chars.length > 14 ? chars.length - 8 : chars.length;
  return (
    <Tip label={name}>
      <span className="file-name selectable" data-file={kind} data-problem={problem ? '' : undefined}>
        <span className="file-head">{chars.slice(0, split).join('')}</span>
        {split < chars.length && <span className="file-tail">{chars.slice(split).join('')}</span>}
      </span>
    </Tip>
  );
}
