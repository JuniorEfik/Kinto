const { ethers } = require('ethers');

// ABI for the handleOps function
const abi = [
    "function handleOps((address sender, uint256 nonce, bytes initCode, bytes callData, uint256 callGasLimit, uint256 verificationGasLimit, uint256 preVerificationGas, uint256 maxFeePerGas, uint256 maxPriorityFeePerGas, bytes paymasterAndData, bytes signature)[] ops, address payable beneficiary) external",
    "function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func)",
    "function approve(address spender, uint256 amount) external",
    "function bridge(address receiver_,uint256 amount_,uint256 msgGasLimit_,address connector_,bytes calldata execPayload_,bytes calldata options_)"
];

// const inputData = "0x1fad948c0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000433704c40f80cbff02e86fd36bc8bac5e31eb0c1000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000007cb2c41ad96f12dae5986006c274278122eabc7a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000b71b00000000000000000000000000000000000000000000000000000000000038270000000000000000000000000000000000000000000000000000000000016e35f000000000000000000000000000000000000000000000000000000000839b68000000000000000000000000000000000000000000000000000000000000a8750000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000005400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000034447e1da2a000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000505de0f7a5d786063348ab5bc31e3a21344fa7b0000000000000000000000000ce2fc6c6bfcf04f2f857338ecf6004381f4149260000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000083266e09f7a330000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000044095ea7b3000000000000000000000000ce2fc6c6bfcf04f2f857338ecf6004381f414926ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000104405e720a000000000000000000000000439b175a246b3fe2189c4c2fa1e6662eb314310300000000000000000000000000000000000000000000003500f396adff150000000000000000000000000000000000000000000000000000000000000007a1200000000000000000000000008feab0b3050320075c8a02dd8f0e404bc7cffb0000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000141842a4eff3efd24c50b63c3cf89cecee245fc2bd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000041a27cf8015e97b2e789a57da7f4cc52ba156626a9d7631fd2e1aea21fe6b9151e15b9a642980bd4f5f9d9614ca8a0afe3b5f71833585df181c502b381a3f166ac1b00000000000000000000000000000000000000000000000000000000000000"
// const inputData = "0x47e1da2a000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000505de0f7a5d786063348ab5bc31e3a21344fa7b0000000000000000000000000ce2fc6c6bfcf04f2f857338ecf6004381f4149260000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000083266e09f7a330000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000044095ea7b3000000000000000000000000ce2fc6c6bfcf04f2f857338ecf6004381f414926ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000104405e720a000000000000000000000000439b175a246b3fe2189c4c2fa1e6662eb314310300000000000000000000000000000000000000000000003500f396adff150000000000000000000000000000000000000000000000000000000000000007a1200000000000000000000000008feab0b3050320075c8a02dd8f0e404bc7cffb0000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
// const inputData = "0x095ea7b3000000000000000000000000ce2fc6c6bfcf04f2f857338ecf6004381f414926ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
const inputData = "0x405e720a000000000000000000000000439b175a246b3fe2189c4c2fa1e6662eb314310300000000000000000000000000000000000000000000003500f396adff150000000000000000000000000000000000000000000000000000000000000007a1200000000000000000000000008feab0b3050320075c8a02dd8f0e404bc7cffb0000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

// Create an interface from the ABI
const iface = new ethers.Interface(abi);

// Decode the calldata
// const decodedData = iface.decodeFunctionData("handleOps", inputData);
const decodedData = iface.decodeFunctionData("bridge", inputData);

console.log(decodedData);


// handle ops
// Result(11) [
//   '0x7Cb2c41aD96f12DaE5986006C274278122EabC7a', // sender
//   2n, // nonce
//   '0x', //initCode
//   '0x47e1da2a000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000505de0f7a5d786063348ab5bc31e3a21344fa7b0000000000000000000000000ce2fc6c6bfcf04f2f857338ecf6004381f4149260000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000083266e09f7a330000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000044095ea7b3000000000000000000000000ce2fc6c6bfcf04f2f857338ecf6004381f414926ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000104405e720a000000000000000000000000439b175a246b3fe2189c4c2fa1e6662eb314310300000000000000000000000000000000000000000000003500f396adff150000000000000000000000000000000000000000000000000000000000000007a1200000000000000000000000008feab0b3050320075c8a02dd8f0e404bc7cffb0000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000', // calldata
//   750000n,
//   230000n,
//   1499999n,
//   138000000n,
//   690000n,
//   '0x1842a4eff3efd24c50b63c3cf89cecee245fc2bd', // paymaster
//   '0xa27cf8015e97b2e789a57da7f4cc52ba156626a9d7631fd2e1aea21fe6b9151e15b9a642980bd4f5f9d9614ca8a0afe3b5f71833585df181c502b381a3f166ac1b' // signature
// ]
// ],
// '0x433704c40F80cBff02e86FD36Bc8baC5e31eB0c1'
// ]

// execute batch
// Result(3) [
//   Result(2) [ // dest
//     '0x505de0f7a5d786063348aB5BC31e3a21344fA7B0',
//     '0xCE2FC6C6bFCF04f2f857338ecF6004381F414926'
//   ],
//   Result(2) [ 0n, 2307217250286131n ], // value
//   Result(2) [ // func: [approve, bride]
//     '0x095ea7b3000000000000000000000000ce2fc6c6bfcf04f2f857338ecf6004381f414926ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
//     '0x405e720a000000000000000000000000439b175a246b3fe2189c4c2fa1e6662eb314310300000000000000000000000000000000000000000000003500f396adff150000000000000000000000000000000000000000000000000000000000000007a1200000000000000000000000008feab0b3050320075c8a02dd8f0e404bc7cffb0000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
//   ]
// ]

// aprove
// Result(2) [
//   '0xCE2FC6C6bFCF04f2f857338ecF6004381F414926',
//   115792089237316195423570985008687907853269984665640564039457584007913129639935n
// ]

// bridge
// Result(6) [
//   '0x439B175A246b3FE2189C4c2FA1e6662eb3143103',
//   977746000000000000000n,
//   500000n,
//   '0x8fEAb0b3050320075c8a02DD8F0e404bc7CFfb00',
//   '0x',
//   '0x'
// ]